# frozen_string_literal: true

module DiscordRDA
  # Invalid Request Bucket - Prevents 1-hour Discord bans by tracking failed requests.
  # Implements the "Invalid Requests" bucket from Discordeno.
  #
  # Discord bans IPs that make too many invalid requests (401, 403, 429) in a short period.
  # This bucket tracks and throttles requests to prevent hitting that limit.
  #
  class InvalidRequestBucket
    # Default values per Discord's documentation
    DEFAULT_LIMIT = 10_000
    DEFAULT_INTERVAL = 10 * 60 * 1000 # 10 minutes in milliseconds

    # @return [Integer] Maximum invalid requests allowed
    attr_reader :limit

    # @return [Integer] Time window in milliseconds
    attr_reader :interval

    # @return [Integer] Current remaining requests
    attr_reader :remaining

    # @return [Logger] Logger instance
    attr_reader :logger

    # Initialize invalid request bucket
    # @param limit [Integer] Maximum invalid requests (default: 10000)
    # @param interval [Integer] Time window in milliseconds (default: 600000)
    # @param logger [Logger] Logger instance
    def initialize(limit: DEFAULT_LIMIT, interval: DEFAULT_INTERVAL, logger: nil)
      @limit = limit
      @interval = interval
      @remaining = limit
      @logger = logger
      @mutex = Mutex.new
      @frozen_at = nil
      @timeout_id = nil
    end

    # Wait until a request is allowed (not rate limited by invalid requests)
    # This blocks if we've hit the invalid request limit
    # @return [void]
    def wait_until_request_available
      @mutex.synchronize do
        if @remaining <= 0 && @frozen_at
          now = Time.now.to_f * 1000
          future = @frozen_at + @interval
          wait_time = [(future - now) / 1000.0, 0].max

          if wait_time > 0
            @logger&.warn('Invalid request bucket limiting', wait_seconds: wait_time.round(2))
            sleep(wait_time)
          end
        end
      end
    end

    # Check if a request is allowed
    # @return [Boolean] True if request can be made
    def request_allowed?
      @mutex.synchronize do
        return true if @remaining > 0
        return true unless @frozen_at

        now = Time.now.to_f * 1000
        now >= (@frozen_at + @interval)
      end
    end

    # Handle a completed request response
    # @param status [Integer] HTTP status code
    # @return [void]
    def handle_request(status)
      # Only count 401, 403, 429, and 502 as invalid requests
      return unless invalid_status?(status)

      @mutex.synchronize do
        @frozen_at ||= Time.now.to_f * 1000
        @remaining -= 1

        @logger&.debug('Invalid request counted', status: status, remaining: @remaining)

        if @remaining <= 1
          @logger&.error('APPROACHING INVALID REQUEST LIMIT! Pausing requests to prevent 1-hour ban.')
          schedule_reset
        end
      end
    end

    # Reset the bucket (after interval has passed)
    # @return [void]
    def reset
      @mutex.synchronize do
        @remaining = @limit
        @frozen_at = nil
        @timeout_id = nil
        @logger&.info('Invalid request bucket reset')
      end
    end

    # Get current status
    # @return [Hash] Bucket status
    def status
      @mutex.synchronize do
        {
          limit: @limit,
          remaining: @remaining,
          interval: @interval,
          frozen_at: @frozen_at,
          request_allowed: request_allowed?
        }
      end
    end

    private

    def invalid_status?(status)
      # Discord counts these as invalid requests
      [401, 403, 429, 502].include?(status)
    end

    def schedule_reset
      return if @timeout_id

      @timeout_id = Thread.new do
        sleep(@interval / 1000.0)
        reset
      end
    end
  end
end
