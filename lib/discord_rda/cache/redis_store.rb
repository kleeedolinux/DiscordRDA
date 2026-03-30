# frozen_string_literal: true

module DiscordRDA
  # Redis-backed cache store.
  # Provides distributed caching with Redis.
  #
  class RedisStore < CacheStore
    # @return [Redis] Redis client
    attr_reader :redis

    # @return [String] Key prefix
    attr_reader :prefix

    # @return [Integer] Default TTL
    attr_reader :default_ttl

    # Initialize Redis store
    # @param redis [Redis] Redis client or connection options
    # @param prefix [String] Key prefix
    # @param default_ttl [Integer] Default TTL in seconds
    def initialize(redis: nil, prefix: 'discord_rda:', default_ttl: 3600)
      @redis = redis.is_a?(Redis) ? redis : Redis.new(redis || {})
      @prefix = prefix
      @default_ttl = default_ttl
    end

    # Get a value from cache
    # @param key [String] Cache key
    # @return [Object, nil] Cached value or nil
    def get(key)
      value = @redis.get(prefixed_key(key))
      return nil unless value

      Marshal.load(value)
    rescue => e
      nil
    end

    # Set a value in cache
    # @param key [String] Cache key
    # @param value [Object] Value to cache
    # @param ttl [Integer] Time to live in seconds
    # @return [void]
    def set(key, value, ttl: nil)
      serialized = Marshal.dump(value)
      ttl ||= @default_ttl

      if ttl
        @redis.setex(prefixed_key(key), ttl, serialized)
      else
        @redis.set(prefixed_key(key), serialized)
      end
    end

    # Delete a value from cache
    # @param key [String] Cache key
    # @return [void]
    def delete(key)
      @redis.del(prefixed_key(key))
    end

    # Check if key exists
    # @param key [String] Cache key
    # @return [Boolean] True if exists
    def exist?(key)
      @redis.exists?(prefixed_key(key))
    end

    # Clear all cached values (matching prefix)
    # @return [void]
    def clear
      keys = @redis.keys("#{@prefix}*")
      @redis.del(*keys) unless keys.empty?
    end

    # Get multiple values
    # @param keys [Array<String>] Cache keys
    # @return [Hash] Key-value pairs
    def mget(keys)
      prefixed = keys.map { |k| prefixed_key(k) }
      values = @redis.mget(prefixed)

      keys.zip(values).to_h do |k, v|
        [k, v ? Marshal.load(v) : nil]
      end
    rescue
      {}
    end

    # Set multiple values
    # @param pairs [Hash] Key-value pairs
    # @param ttl [Integer] Time to live
    # @return [void]
    def mset(pairs, ttl: nil)
      ttl ||= @default_ttl

      @redis.multi do |pipeline|
        pairs.each do |k, v|
          serialized = Marshal.dump(v)
          if ttl
            pipeline.setex(prefixed_key(k), ttl, serialized)
          else
            pipeline.set(prefixed_key(k), serialized)
          end
        end
      end
    end

    # Get keys matching a pattern using SCAN (non-blocking)
    # @param pattern [String, Regexp] Pattern to match
    # @return [Array<String>] Matching keys (without prefix)
    def keys(pattern)
      glob_pattern = pattern.is_a?(Regexp) ? "#{@prefix}*" : "#{@prefix}#{pattern}"
      keys = []

      # Use SCAN to iterate without blocking Redis
      cursor = '0'
      loop do
        cursor, results = @redis.scan(cursor, match: glob_pattern, count: 100)
        keys.concat(results)
        break if cursor == '0'
      end

      # Strip prefix from keys
      keys.map { |k| k.delete_prefix(@prefix) }
    rescue => e
      []
    end

    private

    def prefixed_key(key)
      "#{@prefix}#{key}"
    end
  end
end
