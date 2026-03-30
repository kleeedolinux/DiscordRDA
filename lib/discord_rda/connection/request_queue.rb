# frozen_string_literal: true

module DiscordRDA
  # Request Queue for handling Discord API requests.
  # Implements queue-based request processing from Discordeno.
  #
  class RequestQueue
    # @return [RestClient] REST client
    attr_reader :rest

    # @return [String] Queue URL identifier
    attr_reader :url

    # @return [String] Queue identifier (token prefix)
    attr_reader :identifier

    # @return [Array<Hash>] Pending requests
    attr_reader :pending

    # @return [Integer] Maximum requests per interval
    attr_reader :max

    # @return [Integer] Requests remaining in current window
    attr_reader :remaining

    # @return [Integer] Time window in milliseconds
    attr_reader :interval

    # @return [Integer] Delay before deleting empty queue
    attr_reader :delete_queue_delay

    # Initialize request queue
    # @param rest [RestClient] REST client
    # @param url [String] URL identifier
    # @param identifier [String] Queue identifier
    # @param delete_queue_delay [Integer] Delay before deleting empty queue (ms)
    def initialize(rest, url:, identifier:, delete_queue_delay: 60_000)
      @rest = rest
      @url = url
      @identifier = identifier
      @delete_queue_delay = delete_queue_delay
      @pending = []
      @max = 1
      @remaining = 1
      @interval = 0
      @frozen_at = nil
      @processing = false
      @timeout_id = nil
      @delete_timeout = nil
      @mutex = Mutex.new
      @first_request = true
    end

    # Add a request to the queue and process
    # @param request [Hash] Request options
    # @return [void]
    def make_request(request)
      wait_until_request_available

      @mutex.synchronize do
        @pending << request
        process_pending unless @processing
      end
    end

    # Process pending requests in the queue
    # @return [void]
    def process_pending
      return if @processing || @pending.empty?

      @mutex.synchronize { @processing = true }

      while !@pending.empty?
        @rest.logger&.debug("Queue #{@url} processing #{@pending.length} pending requests")

        # Check if we can make a request
        unless @first_request || request_allowed?
          now = Time.now.to_f * 1000
          future = @frozen_at + @interval
          wait_ms = [future - now, 1000].max
          sleep(wait_ms / 1000.0)
          next
        end

        request = @pending.first
        break unless request

        # Check rate limits before sending
        basic_url = @rest.simplify_url(request[:route], request[:method])

        # Check URL rate limits
        url_reset = @rest.check_rate_limits(basic_url, @identifier)
        if url_reset
          sleep(url_reset / 1000.0)
          next
        end

        # Check bucket rate limits
        if request[:bucket_id]
          bucket_reset = @rest.check_rate_limits(request[:bucket_id], @identifier)
          if bucket_reset
            sleep(bucket_reset / 1000.0)
            next
          end
        end

        @first_request = false
        @remaining -= 1

        # Schedule reset if depleted
        if @remaining == 0 && @interval > 0
          schedule_reset
        end

        # Remove from queue and send
        @mutex.synchronize { @pending.shift }

        # Wait for invalid bucket
        @rest.invalid_bucket.wait_until_request_available

        # Send request
        begin
          @rest.send_request(request)
        rescue => e
          @rest.logger&.error("Queue #{@url} request failed", error: e)
          request[:reject]&.call(error: e) if request[:reject]
        end
      end

      @mutex.synchronize { @processing = false }
      cleanup
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

    # Wait until request is available
    # @return [void]
    def wait_until_request_available
      @mutex.synchronize do
        return if @remaining > 0

        if @frozen_at
          now = Time.now.to_f * 1000
          future = @frozen_at + @interval
          wait_time = [(future - now) / 1000.0, 0].max
          sleep(wait_time) if wait_time > 0
        end
      end
    end

    # Clean up queue if empty
    # @return [void]
    def cleanup
      return unless clearable?

      @rest.logger&.debug("Queue #{@url} scheduling cleanup in #{@delete_queue_delay}ms")

      @delete_timeout&.kill
      @delete_timeout = Thread.new do
        sleep(@delete_queue_delay / 1000.0)

        unless clearable?
          @rest.logger&.debug("Queue #{@url} no longer clearable, restarting processing")
          process_pending
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

    private

    def schedule_reset(interval = nil)
      return if @timeout_id

      interval ||= @interval

      @timeout_id = Thread.new do
        sleep(interval / 1000.0)
        @mutex.synchronize do
          @remaining = @max
          @timeout_id = nil
        end
      end
    end
  end
end
