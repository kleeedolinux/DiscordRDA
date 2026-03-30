# frozen_string_literal: true

module DiscordRDA
  # Typed entity cache with automatic invalidation.
  # Provides methods for caching and retrieving Discord entities.
  #
  class EntityCache
    # @return [CacheStore] Cache store
    attr_reader :store

    # @return [Logger] Logger instance
    attr_reader :logger

    # Entity TTLs in seconds
    TTL = {
      user: 300,
      guild: 60,
      channel: 300,
      message: 60,
      role: 300,
      member: 120
    }.freeze

    # Initialize entity cache
    # @param store [CacheStore] Cache store instance
    # @param logger [Logger] Logger instance
    def initialize(store, logger: nil)
      @store = store
      @logger = logger
    end

    # Cache a user
    # @param user [User] User to cache
    # @return [void]
    def cache_user(user)
      cache(:user, user.id, user)
    end

    # Get a cached user
    # @param user_id [String, Snowflake] User ID
    # @return [User, nil] Cached user
    def user(user_id)
      get(:user, user_id)
    end

    # Cache a guild
    # @param guild [Guild] Guild to cache
    # @return [void]
    def cache_guild(guild)
      cache(:guild, guild.id, guild)
    end

    # Get a cached guild
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Guild, nil] Cached guild
    def guild(guild_id)
      get(:guild, guild_id)
    end

    # Cache a channel
    # @param channel [Channel] Channel to cache
    # @return [void]
    def cache_channel(channel)
      cache(:channel, channel.id, channel)
    end

    # Get a cached channel
    # @param channel_id [String, Snowflake] Channel ID
    # @return [Channel, nil] Cached channel
    def channel(channel_id)
      get(:channel, channel_id)
    end

    # Cache a message
    # @param message [Message] Message to cache
    # @return [void]
    def cache_message(message)
      cache(:message, message.id, message)
    end

    # Get a cached message
    # @param message_id [String, Snowflake] Message ID
    # @return [Message, nil] Cached message
    def message(message_id)
      get(:message, message_id)
    end

    # Cache a role
    # @param role [Role] Role to cache
    # @return [void]
    def cache_role(role)
      cache(:role, role.id, role)
    end

    # Get a cached role
    # @param role_id [String, Snowflake] Role ID
    # @return [Role, nil] Cached role
    def role(role_id)
      get(:role, role_id)
    end

    # Cache a member
    # @param member [Member] Member to cache
    # @param guild_id [String, Snowflake] Guild ID
    # @return [void]
    def cache_member(member, guild_id)
      key = "#{guild_id}:#{member.id}"
      cache(:member, key, member)
    end

    # Get a cached member
    # @param user_id [String, Snowflake] User ID
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Member, nil] Cached member
    def member(user_id, guild_id)
      key = "#{guild_id}:#{user_id}"
      get(:member, key)
    end

    # Invalidate an entity
    # @param type [Symbol] Entity type
    # @param id [String, Snowflake] Entity ID
    # @return [void]
    def invalidate(type, id)
      key = build_key(type, id)
      @store.delete(key)
      @logger&.debug('Invalidated cache', type: type, id: id)
    end

    # Invalidate by guild ID
    # @param guild_id [String, Snowflake] Guild ID
    # @return [void]
    def invalidate_guild(guild_id)
      guild_key = guild_id.to_s
      deleted_count = 0

      # Delete the guild itself
      @store.delete("guild:#{guild_key}")
      deleted_count += 1

      # Delete all members associated with this guild
      if @store.respond_to?(:keys)
        member_keys = @store.keys("member:#{guild_key}:*")
        member_keys.each do |key|
          @store.delete(key)
          deleted_count += 1
        end
      end

      @logger&.debug('Invalidated guild cache', guild_id: guild_id, deleted: deleted_count)
    end

    # Clear all cached entities
    # @return [void]
    def clear
      @store.clear
      @logger&.info('Cleared entity cache')
    end

    # Get cache statistics
    # @return [Hash] Statistics
    def stats
      @store.respond_to?(:stats) ? @store.stats : {}
    end

    private

    def cache(type, id, entity)
      key = build_key(type, id)
      ttl = TTL[type]
      @store.set(key, entity, ttl: ttl)
      @logger&.debug('Cached entity', type: type, id: id)
    end

    def get(type, id)
      key = build_key(type, id)
      @store.get(key)
    end

    def build_key(type, id)
      "#{type}:#{id}"
    end
  end
end
