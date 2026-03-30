# frozen_string_literal: true

require 'lru_redux'

module DiscordRDA
  # In-memory LRU cache store.
  # Provides fast, thread-safe caching with size limits and TTL.
  #
  class MemoryStore < CacheStore
    # Default cache size
    DEFAULT_SIZE = 10_000

    # @return [Integer] Maximum cache size
    attr_reader :max_size

    # @return [Hash] TTL tracking
    attr_reader :ttl_data

    # Initialize memory store
    # @param max_size [Integer] Maximum cache size
    def initialize(max_size: DEFAULT_SIZE)
      @max_size = max_size
      @cache = LruRedux::Cache.new(max_size)
      @ttl_data = {}
      @mutex = Mutex.new
    end

    # Get a value from cache
    # @param key [String] Cache key
    # @return [Object, nil] Cached value or nil if expired/missing
    def get(key)
      @mutex.synchronize do
        check_ttl(key)
        @cache[key]
      end
    end

    # Set a value in cache
    # @param key [String] Cache key
    # @param value [Object] Value to cache
    # @param ttl [Integer] Time to live in seconds
    # @return [void]
    def set(key, value, ttl: nil)
      @mutex.synchronize do
        @cache[key] = value
        @ttl_data[key] = Time.now.utc + ttl if ttl
      end
    end

    # Delete a value from cache
    # @param key [String] Cache key
    # @return [void]
    def delete(key)
      @mutex.synchronize do
        @cache.delete(key)
        @ttl_data.delete(key)
      end
    end

    # Check if key exists and is not expired
    # @param key [String] Cache key
    # @return [Boolean] True if exists
    def exist?(key)
      @mutex.synchronize do
        check_ttl(key)
        @cache.key?(key)
      end
    end

    # Clear all cached values
    # @return [void]
    def clear
      @mutex.synchronize do
        @cache.clear
        @ttl_data.clear
      end
    end

    # Get current cache size
    # @return [Integer] Number of cached items
    def size
      @mutex.synchronize do
        clean_expired
        @cache.size
      end
    end

    # Get cache statistics
    # @return [Hash] Statistics
    def stats
      @mutex.synchronize do
        clean_expired
        {
          size: @cache.size,
          max_size: @max_size,
          ttl_entries: @ttl_data.size
        }
      end
    end

    # Get keys matching a pattern
    # @param pattern [String, Regexp] Pattern to match (supports globs like "member:123:*")
    # @return [Array<String>] Matching keys
    def keys(pattern)
      @mutex.synchronize do
        clean_expired

        regex = if pattern.is_a?(Regexp)
                  pattern
                else
                  # Convert glob pattern to regex
                  regex_str = pattern.gsub('.', '\\.')
                                   .gsub('*', '.*')
                                   .gsub('?', '.')
                  Regexp.new("^#{regex_str}$")
                end

        @cache.keys.select { |k| k.match?(regex) }
      end
    end

    private

    def check_ttl(key)
      ttl = @ttl_data[key]
      return unless ttl

      if Time.now.utc > ttl
        @cache.delete(key)
        @ttl_data.delete(key)
      end
    end

    def clean_expired
      now = Time.now.utc
      expired = @ttl_data.select { |_, ttl| now > ttl }.keys
      expired.each do |key|
        @cache.delete(key)
        @ttl_data.delete(key)
      end
    end
  end
end
