# frozen_string_literal: true

module DiscordRDA
  # Cache store interface.
  # Implementations must provide get, set, delete, and clear methods.
  #
  class CacheStore
    # Get a value from cache
    # @param key [String] Cache key
    # @return [Object, nil] Cached value or nil
    def get(key)
      raise NotImplementedError
    end

    # Set a value in cache
    # @param key [String] Cache key
    # @param value [Object] Value to cache
    # @param ttl [Integer] Time to live in seconds
    # @return [void]
    def set(key, value, ttl: nil)
      raise NotImplementedError
    end

    # Delete a value from cache
    # @param key [String] Cache key
    # @return [void]
    def delete(key)
      raise NotImplementedError
    end

    # Check if key exists
    # @param key [String] Cache key
    # @return [Boolean] True if exists
    def exist?(key)
      !get(key).nil?
    end

    # Clear all cached values
    # @return [void]
    def clear
      raise NotImplementedError
    end

    # Get multiple values
    # @param keys [Array<String>] Cache keys
    # @return [Hash] Key-value pairs
    def mget(keys)
      keys.to_h { |k| [k, get(k)] }
    end

    # Get keys matching a pattern
    # @param pattern [String, Regexp] Pattern to match
    # @return [Array<String>] Matching keys
    def keys(pattern)
      raise NotImplementedError
    end
