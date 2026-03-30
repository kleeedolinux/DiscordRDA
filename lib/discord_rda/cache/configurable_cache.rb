# frozen_string_literal: true

module DiscordRDA
  # Configurable cache manager.
  # By default, caches NOTHING - follows Discordeno philosophy.
  # Users can opt-in to caching only what they need.
  #
  class ConfigurableCache
    # Cache nothing strategy
    STRATEGY_NONE = :none

    # Cache everything strategy
    STRATEGY_FULL = :full

    # Custom strategy - user specifies what to cache
    STRATEGY_CUSTOM = :custom

    # @return [Symbol] Current cache strategy
    attr_reader :strategy

    # @return [CacheStore] Cache store backend
    attr_reader :store

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [Hash] Enabled cache types
    attr_reader :enabled_caches

    # @return [Array<Symbol>] Properties to cache per entity
    attr_reader :cached_properties

    # Initialize configurable cache
    # @param strategy [Symbol] Cache strategy (:none, :full, :custom)
    # @param store [CacheStore] Cache store backend
    # @param logger [Logger] Logger instance
    # @param enabled_caches [Array<Symbol>] Which entity types to cache (for :custom)
    # @param cached_properties [Hash] Which properties to cache per entity
    def initialize(
      strategy: STRATEGY_NONE,
      store: nil,
      logger: nil,
      enabled_caches: [],
      cached_properties: {}
    )
      @strategy = strategy
      @store = store || MemoryStore.new
      @logger = logger
      @enabled_caches = enabled_caches
      @cached_properties = cached_properties

      @logger&.info('Cache initialized', strategy: strategy, enabled: enabled_caches)
    end

    # Cache an entity (only if enabled for this type)
    # @param type [Symbol] Entity type
    # @param id [String, Snowflake] Entity ID
    # @param entity [Entity] Entity to cache
    # @param ttl [Integer] Time to live in seconds
    # @return [void]
    def cache(type, id, entity, ttl: 300)
      return unless should_cache?(type)

      # If custom properties specified, only cache those
      if @cached_properties[type]
        entity = filter_properties(entity, @cached_properties[type])
      end

      key = "#{type}:#{id}"
      @store.set(key, entity, ttl: ttl)

      @logger&.debug('Cached entity', type: type, id: id, strategy: @strategy)
    end

    # Get cached entity
    # @param type [Symbol] Entity type
    # @param id [String, Snowflake] Entity ID
    # @return [Entity, nil] Cached entity or nil
    def get(type, id)
      return nil unless should_cache?(type)

      key = "#{type}:#{id}"
      @store.get(key)
    end

    # Check if entity should be cached
    # @param type [Symbol] Entity type
    # @return [Boolean] True if should cache
    def should_cache?(type)
      case @strategy
      when STRATEGY_NONE
        false
      when STRATEGY_FULL
        true
      when STRATEGY_CUSTOM
        @enabled_caches.include?(type)
      else
        false
      end
    end

    # Invalidate an entity
    # @param type [Symbol] Entity type
    # @param id [String, Snowflake] Entity ID
    # @return [void]
    def invalidate(type, id)
      key = "#{type}:#{id}"
      @store.delete(key)
    end

    # Clear all cached data
    # @return [void]
    def clear
      @store.clear
    end

    # Get cache statistics
    # @return [Hash] Statistics
    def stats
      base_stats = @store.respond_to?(:stats) ? @store.stats : {}

      {
        strategy: @strategy,
        enabled_caches: @enabled_caches,
        **base_stats
      }
    end

    # Create a new cache with different settings (immutable)
    # @param overrides [Hash] Settings to override
    # @return [ConfigurableCache] New cache instance
    def with(**overrides)
      self.class.new(
        strategy: overrides.fetch(:strategy, @strategy),
        store: overrides.fetch(:store, @store),
        logger: overrides.fetch(:logger, @logger),
        enabled_caches: overrides.fetch(:enabled_caches, @enabled_caches),
        cached_properties: overrides.fetch(:cached_properties, @cached_properties)
      )
    end

    private

    def filter_properties(entity, properties)
      return entity unless entity.respond_to?(:to_h)

      data = entity.to_h
      filtered = data.slice(*properties.map(&:to_s))

      # Create new entity with filtered data
      entity.class.new(filtered)
    end
  end
end
