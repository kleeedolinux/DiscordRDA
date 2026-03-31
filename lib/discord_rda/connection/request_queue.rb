# frozen_string_literal: true

module DiscordRDA
  # Production-ready Request Queue with proper Async integration.
  # Handles Discord API requests with automatic rate limiting and retry logic.
  #
  class RequestQueue
    # @return [RestClient] REST client
    attr_reader :rest

    # @return [String] Queue URL identifier
    attr_reader :url

    # @return [String] Queue identifier (token prefix)
    attr_accessor :identifier

    # @return [Array<Hash>] Pending requests
    attr_reader :pending

    # @return [Integer] Maximum requests per interval
    attr_reader :max

    # @return [Integer] Requests remaining in current window
    attr_reader :remaining

    # @return [Integer] Time window in milliseconds
    attr_reader :interval

    # @return [Integer] Delay before deleting empty queue (ms)
    attr_reader :delete_queue_delay

    # @return [Integer] Request timeout in seconds
    attr_reader :request_timeout

    # Initialize request queue
    # @param rest [RestClient] REST client
    # @param url [String] URL identifier
    # @param identifier [String] Queue identifier
    # @param delete_queue_delay [Integer] Delay before deleting empty queue (ms)
    # @param request_timeout [Integer] Request timeout in seconds
    def initialize(rest, url:, identifier:, delete_queue_delay: 60_000, request_timeout: 30)
      @rest = rest
      @url = url
      @identifier = identifier
      @delete_queue_delay = delete_queue_delay
      @request_timeout = request_timeout
      @pending = []
      @max = 1
      @remaining = 1
      @interval = 0
      @frozen_at = nil
      @processing = false
      @reset_timer = nil
      @delete_timeout = nil
      @mutex = Mutex.new
      @first_request = true
      @retry_count = Hash.new(0)
      @max_retries = 3
    end

    # Add a request to the queue and process
    # @param request [Hash] Request options
    # @return [void]
    def make_request(request)
      wait_until_request_available

      @mutex.synchronize do
        @pending << request
        schedule_processing unless @processing
      end
    end

    # Schedule processing asynchronously
    # @return [void]
    def schedule_processing
      Async { process_pending }
    end

    # Process pending requests in the queue with proper async
    # @return [void]
    def process_pending
      return if @processing || @pending.empty?

      @mutex.synchronize { @processing = true }

      loop do
        break if @pending.empty?

        @rest.logger&.debug("Queue #{@url} processing #{@pending.length} pending requests")

        # Check if we can make a request
        unless @first_request || request_allowed?
          wait_time = calculate_wait_time
          if wait_time > 0
            Async { |t| t.sleep(wait_time) }
            next
          end
        end

        request = @mutex.synchronize { @pending.first }
        break unless request

        # Check rate limits before sending
        basic_url = @rest.simplify_url(request[:route], request[:method])

        # Check URL rate limits with async waiting
        url_reset = @rest.check_rate_limits(basic_url, @identifier)
        if url_reset && url_reset > 0
          Async { |t| t.sleep(url_reset / 1000.0) }
          next
        end

        # Check bucket rate limits
        if request[:bucket_id]
          bucket_reset = @rest.check_rate_limits(request[:bucket_id], @identifier)
          if bucket_reset && bucket_reset > 0
            Async { |t| t.sleep(bucket_reset / 1000.0) }
            next
          end
        end

        # Wait for invalid bucket with proper async
        unless @rest.invalid_bucket.request_allowed?
          @rest.invalid_bucket.wait_until_request_available
        end

        @first_request = false
        @remaining -= 1

        # Schedule reset if depleted
        if @remaining == 0 && @interval > 0
          schedule_reset
        end

        # Remove from queue and send
        @mutex.synchronize { @pending.shift }

        # Send request with timeout and retry logic
        send_with_retry(request)
      end

      @mutex.synchronize { @processing = false }
      cleanup
    end

    # Send request with retry logic
    # @param request [Hash] Request data
    # @return [void]
    def send_with_retry(request)
      request_id = request.object_id
      attempts = 0

      loop do
        attempts += 1

        begin
          # Send with timeout
          result = nil
          Async do |task|
            task.with_timeout(@request_timeout) do
              result = @rest.send_request(request)
            end
          rescue Async::TimeoutError
            raise TimeoutError, "Request timed out after #{@request_timeout}s"
          end

          # Success - reset retry count
          @retry_count.delete(request_id)
          request[:resolve]&.call(result) if request[:resolve]
          return result

        rescue RateLimitedError => e
          # Wait and retry
          wait_time = e.retry_after || 1.0
          @rest.logger&.warn('Rate limited, retrying', route: request[:route], wait: wait_time, attempt: attempts)
          Async { |t| t.sleep(wait_time) }
          next if attempts < @max_retries

          # Max retries reached
          request[:reject]&.call(error: e) if request[:reject]
          raise

        rescue ServerError => e
          # Retry server errors with backoff
          if attempts < @max_retries
            backoff = 2 ** attempts
            @rest.logger&.warn('Server error, retrying with backoff', route: request[:route], backoff: backoff, attempt: attempts)
            Async { |t| t.sleep(backoff) }
            next
          end

          request[:reject]&.call(error: e) if request[:reject]
          raise

        rescue => e
          # Other errors - don't retry
          @retry_count.delete(request_id)
          @rest.logger&.error("Queue #{@url} request failed", error: e, route: request[:route], attempt: attempts)
          request[:reject]&.call(error: e) if request[:reject]
          raise
        end
      end
    end

    # Handle completed request response (update rate limit info)
    # @param headers [Hash] Response headers
    # @return [void]
    def handle_completed_request(headers)
      @mutex.synchronize do
        if headers[:max] == 0
          @remaining += 1
          return
        end

        @frozen_at ||= Time.now.to_f * 1000
        @interval = headers[:interval] if headers[:interval]
        @remaining = headers[:remaining] if headers[:remaining]

        if @remaining <= 1 && headers[:interval]
          schedule_reset(headers[:interval])
        end
      end
    end

    # Check if request is allowed
    # @return [Boolean] True if request can be made
    def request_allowed?
      @mutex.synchronize do
        return true if @remaining > 0
        return true unless @frozen_at

        now = Time.now.to_f * 1000
        now >= (@frozen_at + @interval)
      end
    end

    # Wait until request is available with async support
    # @return [void]
    def wait_until_request_available
      @mutex.synchronize do
        return if @remaining > 0

        if @frozen_at
          now = Time.now.to_f * 1000
          future = @frozen_at + @interval
          wait_time = [(future - now) / 1000.0, 0].max

          if wait_time > 0
            @mutex.unlock
            if defined?(Async::Task) && Async::Task.current?
              Async::Task.current.sleep(wait_time)
            else
              sleep(wait_time)
            end
            @mutex.lock
          end
        end
      end
    end

    # Calculate wait time for rate limit
    # @return [Float] Seconds to wait
    def calculate_wait_time
      @mutex.synchronize do
        return 0 unless @frozen_at

        now = Time.now.to_f * 1000
        future = @frozen_at + @interval
        [(future - now) / 1000.0, 1000].max / 1000.0
      end
    end

    # Clean up queue if empty
    # @return [void]
    def cleanup
      return unless clearable?

      @rest.logger&.debug("Queue #{@url} scheduling cleanup in #{@delete_queue_delay}ms")

      @delete_timeout&.stop rescue nil

      @delete_timeout = Async do |task|
        task.sleep(@delete_queue_delay / 1000.0)

        unless clearable?
          @rest.logger&.debug("Queue #{@url} no longer clearable, restarting processing")
          schedule_processing
          return
        end

        @rest.logger&.debug("Queue #{@url} deleting")
        @rest.queues.delete("#{@identifier}#{@url}")
      end
    end

    # Check if queue can be cleared
    # @return [Boolean] True if queue can be deleted
    def clearable?
      @mutex.synchronize do
        @pending.empty? && !@processing
      end
    end

    # Get queue status
    # @return [Hash] Queue status
    def status
      @mutex.synchronize do
        {
          url: @url,
          identifier: @identifier,
          pending_count: @pending.length,
          processing: @processing,
          max: @max,
          remaining: @remaining,
          interval: @interval,
          frozen_at: @frozen_at,
          request_allowed: request_allowed?
        }
      end
    end

    private

    def schedule_reset(interval = nil)
      return if @reset_timer

      interval ||= @interval

      @reset_timer = Async do |task|
        task.sleep(interval / 1000.0)
        @mutex.synchronize do
          @remaining = @max
          @reset_timer = nil
        end
      end
    end
  end

  class TimeoutError < StandardError; end
end
