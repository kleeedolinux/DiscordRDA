# frozen_string_literal: true

require 'async/semaphore'

module DiscordRDA
  # Rate limiter for Discord REST API.
  # Implements token bucket algorithm per route.
  #
  class RateLimiter
    # Rate limit info structure
    RateLimitInfo = Struct.new(:limit, :remaining, :reset, :reset_after, :bucket, keyword_init: true)

    # @return [Hash<String, RateLimitInfo>] Rate limit info per route
    attr_reader :limits

    # @return [Logger] Logger instance
    attr_reader :logger

    # Initialize rate limiter
    # @param logger [Logger] Logger instance
    def initialize(logger: nil)
      @logger = logger
      @limits = {}
      @mutex = Mutex.new
      @global_reset = nil
    end

    # Acquire permission to make a request
    # @param route [String] Route identifier
    # @return [void]
    def acquire(route)
      # Wait for global rate limit
      wait_for_global if @global_reset

      # Check route-specific limit
      info = @limits[route]
      return unless info

      if info.remaining <= 0
        wait_time = info.reset_after
        if wait_time > 0
          @logger&.info('Rate limited, waiting', route: route, seconds: wait_time)
          sleep(wait_time)
        end
      end
    end

    # Update rate limit info from response headers
    # @param route [String] Route identifier
    # @param response [Protocol::HTTP::Response] HTTP response
    # @return [void]
    def update(route, response)
      headers = response.headers

      # Check for global rate limit
      global = headers['x-ratelimit-global']
      if global == 'true'
        @global_reset = Time.now + (headers['retry-after'].to_f / 1000.0)
        @logger&.warn('Global rate limit hit', reset_at: @global_reset)
        return
      end

      # Parse rate limit headers
      limit = headers['x-ratelimit-limit']&.to_i
      remaining = headers['x-ratelimit-remaining']&.to_i
      reset = headers['x-ratelimit-reset']&.to_f
      reset_after = headers['x-ratelimit-reset-after']&.to_f
      bucket = headers['x-ratelimit-bucket']

      return unless limit

      info = RateLimitInfo.new(
        limit: limit,
        remaining: remaining || 0,
        reset: reset ? Time.at(reset) : nil,
        reset_after: reset_after || 0,
        bucket: bucket
      )

      @mutex.synchronize { @limits[route] = info }
      @logger&.debug('Updated rate limit', route: route, bucket: bucket, remaining: remaining)
    end

    # Get rate limit info for a route
    # @param route [String] Route identifier
    # @return [RateLimitInfo, nil] Rate limit info
    def info(route)
      @limits[route]
    end

    # Check if route is rate limited
    # @param route [String] Route identifier
    # @return [Boolean] True if limited
    def limited?(route)
      info = @limits[route]
      return false unless info

      info.remaining <= 0 && info.reset_after > 0
    end

    # Get reset time for a route
    # @param route [String] Route identifier
    # @return [Time, nil] Reset time
    def reset_time(route)
      info = @limits[route]&.reset
    end

    # Clear all rate limits
    # @return [void]
    def clear
      @mutex.synchronize { @limits.clear }
      @global_reset = nil
    end

    private

    def wait_for_global
      return unless @global_reset

      now = Time.now
      if now < @global_reset
        wait_time = @global_reset - now
        @logger&.warn('Waiting for global rate limit', seconds: wait_time)
        sleep(wait_time)
      end
      @global_reset = nil
    end
  end
end
