# frozen_string_literal: true

module DiscordRDA
  # Production-ready Invalid Request Bucket - Prevents 1-hour Discord bans.
  # Implements global request pausing when approaching invalid request limits.
  #
  class InvalidRequestBucket
    # Default values per Discord's documentation
    DEFAULT_LIMIT = 10_000
    DEFAULT_INTERVAL = 10 * 60 * 1000 # 10 minutes in milliseconds
    WARNING_THRESHOLD = 100 # Warn when remaining drops below this
    PAUSE_THRESHOLD = 50 # Pause all requests when remaining drops below this

    # @return [Integer] Maximum invalid requests allowed
    attr_reader :limit

    # @return [Integer] Time window in milliseconds
    attr_reader :interval

    # @return [Integer] Current remaining requests
    attr_reader :remaining

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [Boolean] Whether globally paused due to approaching limit
    attr_reader :globally_paused

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
      @reset_timer = nil
      @globally_paused = false
      @pause_condition = Async::Condition.new
    end

    # Wait until a request is allowed (not rate limited by invalid requests)
    # Blocks if we've hit the invalid request limit or if globally paused
    # @return [void]
    def wait_until_request_available
      @mutex.synchronize do
        # Wait if globally paused
        while @globally_paused
          @logger&.warn('Waiting: Globally paused due to invalid request limit')
          @mutex.unlock
          @pause_condition.wait
          @mutex.lock
        end

        if @remaining <= PAUSE_THRESHOLD && !@globally_paused
          @globally_paused = true
          @logger&.error('GLOBAL PAUSE ACTIVATED: Approaching invalid request limit!', remaining: @remaining)
        end

        if @remaining <= 0 && @frozen_at
          now = Time.now.to_f * 1000
          future = @frozen_at + @interval
          wait_time = [(future - now) / 1000.0, 0].max

          if wait_time > 0
            @logger&.error('Invalid request bucket exhausted! Waiting to prevent 1-hour ban.', wait_seconds: wait_time.round(2))
            @mutex.unlock
            sleep(wait_time)
            @mutex.lock
          end
        end
      end
    end

    # Check if a request is allowed
    # @return [Boolean] True if request can be made
    def request_allowed?
      @mutex.synchronize do
        return false if @globally_paused
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

        @logger&.debug('Invalid request counted', status: status, remaining: @remaining, limit: @limit)

        # Schedule automatic reset
        schedule_reset unless @reset_timer

        # Check thresholds
        if @remaining == WARNING_THRESHOLD
          @logger&.warn('Approaching invalid request limit!', remaining: @remaining)
        elsif @remaining == PAUSE_THRESHOLD
          @globally_paused = true
          @logger&.error('CRITICAL: Pausing all requests to prevent 1-hour Discord ban!', remaining: @remaining)
        elsif @remaining <= 0
          @logger&.error('INVALID REQUEST LIMIT REACHED! All requests blocked for 10 minutes.')
        end
      end
    end

    # Release global pause (call after interval or manual intervention)
    # @return [void]
    def release_pause
      @mutex.synchronize do
        was_paused = @globally_paused
        @globally_paused = false
        @logger&.info('Global pause released. Resuming normal request processing.') if was_paused
        @pause_condition.signal
      end
    end

    # Reset the bucket (after interval has passed)
    # @return [void]
    def reset
      @mutex.synchronize do
        old_remaining = @remaining
        @remaining = @limit
        @frozen_at = nil
        @reset_timer = nil
        was_paused = @globally_paused
        @globally_paused = false

        if old_remaining < WARNING_THRESHOLD
          @logger&.info('Invalid request bucket reset', previous_remaining: old_remaining)
        end

        @pause_condition.signal if was_paused
      end
    end

    # Get current status with detailed information
    # @return [Hash] Bucket status
    def status
      @mutex.synchronize do
        now = Time.now.to_f * 1000
        reset_in = if @frozen_at && @remaining <= 0
          [(@frozen_at + @interval - now) / 1000.0, 0].max
        else
          nil
        end

        {
          limit: @limit,
          remaining: @remaining,
          used: @limit - @remaining,
          interval: @interval,
          interval_minutes: @interval / 60000.0,
          frozen_at: @frozen_at ? Time.at(@frozen_at / 1000.0) : nil,
          reset_in_seconds: reset_in,
          globally_paused: @globally_paused,
          request_allowed: request_allowed?,
          warning_threshold: WARNING_THRESHOLD,
          pause_threshold: PAUSE_THRESHOLD,
          healthy: @remaining > WARNING_THRESHOLD
        }
      end
    end

    # Check if bucket is healthy
    # @return [Boolean] True if well above warning threshold
    def healthy?
      @mutex.synchronize { @remaining > WARNING_THRESHOLD }
    end

    # Get percentage of remaining requests
    # @return [Float] Percentage (0-100)
    def health_percentage
      @mutex.synchronize { (@remaining.to_f / @limit) * 100 }
    end

    private

    def invalid_status?(status)
      # Discord counts these as invalid requests
      [401, 403, 429, 502].include?(status)
    end

    def schedule_reset
      return if @reset_timer

      @reset_timer = Async do |task|
        task.sleep(@interval / 1000.0)
        reset
      end
    end
  end
end
