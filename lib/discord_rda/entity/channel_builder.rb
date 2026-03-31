# frozen_string_literal: true

module DiscordRDA
  # DSL for building channel modifications.
  # Provides a fluent interface for modifying channel properties.
  #
  class ChannelBuilder
    # @return [Hash] Channel data being built
    attr_reader :data

    # Initialize a new channel builder
    # @param name [String] Channel name
    def initialize(name = nil)
      @data = {}
      @data[:name] = name if name
    end

    # Set channel name
    # @param name [String] Channel name (1-100 characters)
    # @return [self]
    def name(name)
      @data[:name] = name
      self
    end

    # Set channel type
    # @param type [Integer, Symbol] Channel type (0=guild_text, 2=guild_voice, etc.)
    # @return [self]
    def type(type)
      @data[:type] = type.is_a?(Symbol) ? Channel::TYPES[type] : type
      self
    end

    # Set channel topic
    # @param topic [String] Channel topic (0-1024 characters for text, 0-4096 for forum)
    # @return [self]
    def topic(topic)
      @data[:topic] = topic
      self
    end

    # Set channel bitrate (for voice channels)
    # @param bitrate [Integer] Bitrate in bits (8000-384000, or 8000-128000 for stage)
    # @return [self]
    def bitrate(bitrate)
      @data[:bitrate] = bitrate
      self
    end

    # Set user limit (for voice channels)
    # @param limit [Integer] User limit (0-99, 0 = unlimited)
    # @return [self]
    def user_limit(limit)
      @data[:user_limit] = limit
      self
    end

    # Set rate limit per user (slowmode)
    # @param seconds [Integer] Seconds between messages (0-21600)
    # @return [self]
    def slowmode(seconds)
      @data[:rate_limit_per_user] = seconds
      self
    end

    # Set channel position
    # @param position [Integer] Position in the left-hand listing
    # @return [self]
    def position(position)
      @data[:position] = position
      self
    end

    # Set parent category ID
    # @param category_id [String, Snowflake] Parent category ID
    # @return [self]
    def parent(category_id)
      @data[:parent_id] = category_id.to_s
      self
    end

    # Set NSFW flag
    # @param nsfw [Boolean] Whether the channel is NSFW
    # @return [self]
    def nsfw(nsfw = true)
      @data[:nsfw] = nsfw
      self
    end

    # Set default auto archive duration (for threads)
    # @param minutes [Integer] Duration in minutes (60, 1440, 4320, 10080)
    # @return [self]
    def default_auto_archive_duration(minutes)
      @data[:default_auto_archive_duration] = minutes
      self
    end

    # Set default thread rate limit per user
    # @param seconds [Integer] Seconds between messages in threads
    # @return [self]
    def default_thread_slowmode(seconds)
      @data[:default_thread_rate_limit_per_user] = seconds
      self
    end

    # Set permission overwrites
    # @param overwrites [Array<Hash>] Permission overwrites array
    # @return [self]
    def permission_overwrites(overwrites)
      @data[:permission_overwrites] = overwrites.map { |o| normalize_overwrite(o) }
      self
    end

    # Add a single permission overwrite
    # @param id [String, Snowflake] Role or user ID
    # @param type [Integer] 0 for role, 1 for member
    # @param allow [Integer, String] Allowed permissions bitfield
    # @param deny [Integer, String] Denied permissions bitfield
    # @return [self]
    def add_overwrite(id:, type:, allow: 0, deny: 0)
      @data[:permission_overwrites] ||= []
      @data[:permission_overwrites] << {
        id: id.to_s,
        type: type,
        allow: allow.is_a?(Integer) ? allow.to_s : allow,
        deny: deny.is_a?(Integer) ? deny.to_s : deny
      }
      self
    end

    # Set channel flags
    # @param flags [Integer] Channel flags bitfield
    # @return [self]
    def flags(flags)
      @data[:flags] = flags
      self
    end

    # Set available tags (for forum channels)
    # @param tags [Array<Hash>] Available tags
    # @return [self]
    def available_tags(tags)
      @data[:available_tags] = tags
      self
    end

    # Set default sort order (for forum channels)
    # @param order [Integer] Default sort order type
    # @return [self]
    def default_sort_order(order)
      @data[:default_sort_order] = order
      self
    end

    # Set default forum layout (for forum channels)
    # @param layout [Integer] Default forum layout view
    # @return [self]
    def default_forum_layout(layout)
      @data[:default_forum_layout] = layout
      self
    end

    # Set default reaction emoji (for forum channels)
    # @param emoji [Hash] Default emoji for forum posts
    # @return [self]
    def default_reaction_emoji(emoji)
      @data[:default_reaction_emoji] = emoji
      self
    end

    # Set video quality mode (for voice channels)
    # @param mode [Integer] Video quality mode (1=auto, 2=full)
    # @return [self]
    def video_quality_mode(mode)
      @data[:video_quality_mode] = mode
      self
    end

    # Convert builder to hash
    # @return [Hash] Channel data hash
    def to_h
      @data.dup
    end

    # Build and return the channel data
    # @return [Hash] Channel data
    def build
      to_h
    end

    private

    def normalize_overwrite(overwrite)
      {
        id: overwrite[:id] || overwrite['id'],
        type: overwrite[:type] || overwrite['type'],
        allow: (overwrite[:allow] || overwrite['allow'] || 0).to_s,
        deny: (overwrite[:deny] || overwrite['deny'] || 0).to_s
      }
    end
  end

  # DSL for creating channel invites
  class InviteBuilder
    # @return [Hash] Invite data being built
    attr_reader :data

    def initialize
      @data = {}
    end

    # Set max age in seconds
    # @param seconds [Integer] Max age (0 = never expires, max 604800)
    # @return [self]
    def max_age(seconds)
      @data[:max_age] = seconds
      self
    end

    # Set max uses
    # @param uses [Integer] Max uses (0 = unlimited, max 100)
    # @return [self]
    def max_uses(uses)
      @data[:max_uses] = uses
      self
    end

    # Set temporary membership
    # @param temporary [Boolean] Whether invite grants temporary membership
    # @return [self]
    def temporary(temporary = true)
      @data[:temporary] = temporary
      self
    end

    # Set unique invite
    # @param unique [Boolean] Whether to create unique URL
    # @return [self]
    def unique(unique = true)
      @data[:unique] = unique
      self
    end

    # Set target type
    # @param type [Integer] Target type (1=stream, 2=embedded_application)
    # @return [self]
    def target_type(type)
      @data[:target_type] = type
      self
    end

    # Set target user ID
    # @param user_id [String, Snowflake] Target user ID
    # @return [self]
    def target_user(user_id)
      @data[:target_user_id] = user_id.to_s
      self
    end

    # Set target application ID
    # @param app_id [String, Snowflake] Target application ID
    # @return [self]
    def target_application(app_id)
      @data[:target_application_id] = app_id.to_s
      self
    end

    # Convert to hash
    # @return [Hash] Invite data
    def to_h
      @data.dup
    end

    # Build and return invite data
    # @return [Hash] Invite data
    def build
      to_h
    end
  end
end
