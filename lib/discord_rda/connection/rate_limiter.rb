# frozen_string_literal: true

require 'async/semaphore'
require 'async/condition'

module DiscordRDA
  # Production-ready Rate Limiter for Discord REST API.
  # Implements precise token bucket algorithm with async timer-based resets.
  #
  class RateLimiter
    # Rate limit info structure
    RateLimitInfo = Struct.new(:limit, :remaining, :reset, :reset_after, :bucket, :last_updated, keyword_init: true)

    # @return [Hash<String, RateLimitInfo>] Rate limit info per route
    attr_reader :limits

    # @return [Hash<String, Array<Async::Condition>]>] Waiters per route
    attr_reader :waiters

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [Float] Global rate limit reset timestamp
    attr_reader :global_reset_at

    # Initialize rate limiter
    # @param logger [Logger] Logger instance
    def initialize(logger: nil)
      @logger = logger
      @limits = {}
      @waiters = Hash.new { |h, k| h[k] = [] }
      @mutex = Mutex.new
      @global_reset_at = nil
      @timers = {}
      @semaphore = Async::Semaphore.new(1)
    end

    # Acquire permission to make a request with precise timing
    # @param route [String] Route identifier
    # @return [void]
    def acquire(route)
      # Check global rate limit first
      wait_for_global if @global_reset_at

      # Check route-specific limit with precise timing
      info = @mutex.synchronize { @limits[route] }
      return unless info

      if info.remaining <= 0 && info.reset_after > 0
        now = Time.now.to_f
        wait_time = [info.reset_after - (now - info.last_updated.to_f), 0].max

        if wait_time > 0
          @logger&.info('Rate limited, waiting', route: route, seconds: wait_time.round(3), bucket: info.bucket)
          precise_sleep(wait_time)
        end
      end
    end

    # Update rate limit info from response headers with precise timing
    # @param route [String] Route identifier
    # @param response [Protocol::HTTP::Response] HTTP response
    # @return [void]
    def update(route, response)
      headers = response.headers

      # Check for global rate limit
      global = headers['x-ratelimit-global']
      if global == 'true'
        retry_after = headers['retry-after']&.to_f || 1.0
        @global_reset_at = Time.now.to_f + retry_after
        @logger&.error('Global rate limit hit', reset_in: retry_after)
        schedule_global_reset(retry_after)
        notify_waiters(route)
        return
      end

      # Parse rate limit headers
      limit = headers['x-ratelimit-limit']&.to_i
      remaining = headers['x-ratelimit-remaining']&.to_i
      reset = headers['x-ratelimit-reset']&.to_f
      reset_after = headers['x-ratelimit-reset-after']&.to_f
      bucket = headers['x-ratelimit-bucket']

      return unless limit

      now = Time.now
      info = RateLimitInfo.new(
        limit: limit,
        remaining: remaining || 0,
        reset: reset ? Time.at(reset) : nil,
        reset_after: reset_after || 0,
        bucket: bucket,
        last_updated: now
      )

      @mutex.synchronize { @limits[route] = info }

      # Schedule precise reset timer if depleted
      if remaining && remaining <= 0 && reset_after && reset_after > 0
        schedule_route_reset(route, reset_after)
      end

      @logger&.debug('Rate limit updated', route: route, bucket: bucket, remaining: remaining, reset_after: reset_after&.round(3))
    end

    # Get rate limit info for a route
    # @param route [String] Route identifier
    # @return [RateLimitInfo, nil] Rate limit info
    def info(route)
      @mutex.synchronize { @limits[route] }
    end

    # Check if route is rate limited
    # @param route [String] Route identifier
    # @return [Boolean] True if limited
    def limited?(route)
      info = @mutex.synchronize { @limits[route] }
      return false unless info

      if info.remaining > 0
        false
      elsif info.reset_after <= 0
        false
      else
        now = Time.now.to_f
        elapsed = now - info.last_updated.to_f
        elapsed < info.reset_after
      end
    end

    # Get time until reset for a route
    # @param route [String] Route identifier
    # @return [Float, nil] Seconds until reset, or nil if not limited
    def time_until_reset(route)
      info = @mutex.synchronize { @limits[route] }
      return nil unless info
      return nil if info.remaining > 0

      elapsed = Time.now.to_f - info.last_updated.to_f
      [info.reset_after - elapsed, 0].max
    end

    # Get reset time for a route
    # @param route [String] Route identifier
    # @return [Time, nil] Reset time
    def reset_time(route)
      @mutex.synchronize { @limits[route]&.reset }
    end

    # Get bucket ID for a route
    # @param route [String] Route identifier
    # @return [String, nil] Bucket ID
    def bucket_id(route)
      @mutex.synchronize { @limits[route]&.bucket }
    end

    # Wait for a route to be available (async-friendly)
    # @param route [String] Route identifier
    # @return [void]
    def wait_for_route(route)
      return unless limited?(route)

      wait_time = time_until_reset(route)
      return unless wait_time && wait_time > 0

      condition = Async::Condition.new
      @mutex.synchronize { @waiters[route] << condition }

      @logger&.debug('Waiting for route', route: route, seconds: wait_time.round(3))

      Async do |task|
        task.sleep(wait_time)
        condition.signal
      end

      condition.wait
    end

    # Clear all rate limits
    # @return [void]
    def clear
      @mutex.synchronize do
        @limits.clear
        @timers.each_value(&:stop) if @timers
        @timers.clear
        @global_reset_at = nil
      end
    end

    # Get comprehensive status
    # @return [Hash] Rate limiter status
    def status
      @mutex.synchronize do
        {
          global_limited: @global_reset_at && Time.now.to_f < @global_reset_at,
          global_reset_in: @global_reset_at ? [@global_reset_at - Time.now.to_f, 0].max : nil,
          routes_tracked: @limits.size,
          routes: @limits.transform_values do |info|
            {
              limit: info.limit,
              remaining: info.remaining,
              reset_after: info.reset_after,
              bucket: info.bucket,
              limited: limited?(@limits.key(info))
            }
          end
        }
      end
    end

    private

    def wait_for_global
      return unless @global_reset_at

      now = Time.now.to_f
      if now < @global_reset_at
        wait_time = @global_reset_at - now
        @logger&.warn('Waiting for global rate limit', seconds: wait_time.round(3))
        precise_sleep(wait_time)
      end
      @global_reset_at = nil
    end

    def precise_sleep(seconds)
      return if seconds <= 0

      # Use Async sleep for async context, regular sleep otherwise
      if defined?(Async::Task) && Async::Task.current?
        Async::Task.current.sleep(seconds)
      else
        sleep(seconds)
      end
    end

    def schedule_global_reset(seconds)
      return if seconds <= 0

      Async do |task|
        task.sleep(seconds)
        @global_reset_at = nil
        notify_all_waiters
      end
    end

    def schedule_route_reset(route, seconds)
      return if seconds <= 0

      # Cancel existing timer
      @timers[route]&.stop

      @timers[route] = Async do |task|
        task.sleep(seconds)
        @mutex.synchronize do
          if @limits[route]
            @limits[route] = @limits[route].dup
            @limits[route].remaining = @limits[route].limit
            @limits[route].last_updated = Time.now
          end
        end
        notify_waiters(route)
      end
    end

    def notify_waiters(route)
      waiters = @mutex.synchronize { @waiters.delete(route) || [] }
      waiters.each(&:signal)
    end

    def notify_all_waiters
      waiters = @mutex.synchronize do
        all = @waiters.values.flatten
        @waiters.clear
        all
      end
      waiters.each(&:signal)
    end
  end
end
