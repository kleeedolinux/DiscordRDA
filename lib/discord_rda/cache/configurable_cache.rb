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
      return entity if properties.nil? || properties.empty?

      data = entity.to_h
      # Support nested property selection with dot notation (e.g., "author.username")
      filtered = {}
      properties.each do |prop|
        if prop.to_s.include?('.')
          parts = prop.to_s.split('.')
          current = data
          current_filtered = filtered

          parts.each_with_index do |part, idx|
            if idx == parts.length - 1
              current_filtered[part] = current[part] if current && current.key?(part)
            else
              current_filtered[part] ||= {}
              current = current&.dig(part)
              current_filtered = current_filtered[part]
            end
          end
        else
          filtered[prop.to_s] = data[prop.to_s] if data.key?(prop.to_s)
        end
      end

      # Preserve ID if it's a filtered entity
      filtered['id'] = data['id'] if data.key?('id') && !filtered.key?('id')

      # Create new entity with filtered data
      entity.class.new(filtered)
    end

    # Advanced property filtering with transforms
    # @param entity [Entity] Entity to filter
    # @param config [Hash] Filter config with :only, :except, :transform options
    # @return [Entity] Filtered entity
    def advanced_filter(entity, config = {})
      return entity unless entity.respond_to?(:to_h)

      data = entity.to_h

      # Apply :only filter
      if config[:only]
        data = data.slice(*config[:only].map(&:to_s))
      end

      # Apply :except filter
      if config[:except]
        data = data.except(*config[:except].map(&:to_s))
      end

      # Apply transforms
      if config[:transform]
        config[:transform].each do |key, transform|
          key_str = key.to_s
          data[key_str] = transform.call(data[key_str]) if data.key?(key_str)
        end
      end

      entity.class.new(data)
    end

    # Filter entities by custom predicate
    # @param type [Symbol] Entity type
    # @yield Block to filter entities
    # @return [Array<Entity>] Filtered entities
    def filter_by(type)
      return [] unless block_given?
      return [] unless should_cache?(type)

      pattern = "#{type}:*"
      all = @store.scan(pattern)
      all.select { |_, entity| yield(entity) }.map { |_, entity| entity }
    end

    # Get filtered properties configuration for an entity type
    # @param type [Symbol] Entity type
    # @return [Array<Symbol>, nil] Properties to cache, or nil for all
    def filter_for(type)
      @cached_properties[type]
    end

    # Set filtered properties for an entity type
    # @param type [Symbol] Entity type
    # @param properties [Array<Symbol>] Properties to cache
    # @return [void]
    def set_filter(type, *properties)
      @cached_properties[type] = properties.flatten
    end

    # Clear filter for an entity type
    # @param type [Symbol] Entity type
    # @return [void]
    def clear_filter(type)
      @cached_properties.delete(type)
    end

    # Batch cache entities with property filtering
    # @param type [Symbol] Entity type
    # @param entities [Array<Entity>] Entities to cache
    # @param ttl [Integer] Time to live in seconds
    # @return [void]
    def cache_batch(type, entities, ttl: 300)
      return unless should_cache?(type)

      entities.each do |entity|
        cache(type, entity.id, entity, ttl: ttl) if entity.respond_to?(:id)
      end
    end

    # Get multiple entities by IDs
    # @param type [Symbol] Entity type
    # @param ids [Array<String, Snowflake>] Entity IDs
    # @return [Array<Entity>] Found entities
    def get_many(type, ids)
      return [] unless should_cache?(type)

      ids.map { |id| get(type, id) }.compact
    end

    # Invalidate multiple entities
    # @param type [Symbol] Entity type
    # @param ids [Array<String, Snowflake>] Entity IDs
    # @return [void]
    def invalidate_many(type, ids)
      ids.each { |id| invalidate(type, id) }
    end

    # Invalidate by pattern
    # @param pattern [String] Pattern to match (e.g., "guild:*:members")
    # @return [Integer] Number of entries invalidated
    def invalidate_pattern(pattern)
      keys = @store.scan(pattern).map { |k, _| k }
      keys.each { |k| @store.delete(k) }
      keys.size
    end
  end
end
