# frozen_string_literal: true

module DiscordRDA
  # Represents a Discord channel.
  # Can be text, voice, category, DM, thread, etc.
  #
  class Channel < Entity
    # Channel types
    TYPES = {
      guild_text: 0,
      dm: 1,
      guild_voice: 2,
      group_dm: 3,
      guild_category: 4,
      guild_announcement: 5,
      announcement_thread: 10,
      public_thread: 11,
      private_thread: 12,
      guild_stage_voice: 13,
      guild_directory: 14,
      guild_forum: 15,
      guild_media: 16
    }.freeze

    attribute :type, type: :integer
    attribute :guild_id, type: :snowflake
    attribute :position, type: :integer, default: 0
    attribute :name, type: :string
    attribute :topic, type: :string
    attribute :nsfw, type: :boolean, default: false
    attribute :last_message_id, type: :snowflake
    attribute :bitrate, type: :integer
    attribute :user_limit, type: :integer
    attribute :rate_limit_per_user, type: :integer, default: 0
    attribute :recipients, type: :array, default: []
    attribute :icon, type: :string
    attribute :owner_id, type: :snowflake
    attribute :application_id, type: :snowflake
    attribute :parent_id, type: :snowflake
    attribute :last_pin_timestamp, type: :time
    attribute :rtc_region, type: :string
    attribute :video_quality_mode, type: :integer, default: 1
    attribute :message_count, type: :integer
    attribute :member_count, type: :integer
    attribute :thread_metadata, type: :hash
    attribute :member, type: :hash
    attribute :default_auto_archive_duration, type: :integer
    attribute :permissions, type: :string
    attribute :flags, type: :integer, default: 0
    attribute :total_message_sent, type: :integer
    attribute :available_tags, type: :array, default: []
    attribute :applied_tags, type: :array, default: []
    attribute :default_reaction_emoji, type: :hash
    attribute :default_thread_rate_limit_per_user, type: :integer
    attribute :default_sort_order, type: :integer
    attribute :default_forum_layout, type: :integer

    # Get channel type as symbol
    # @return [Symbol] Channel type
    def channel_type
      TYPES.key(type) || :unknown
    end

    # Check if this is a text channel
    # @return [Boolean] True if text channel
    def text?
      type == 0 || type == 5
    end

    # Check if this is a voice channel
    # @return [Boolean] True if voice channel
    def voice?
      type == 2 || type == 13
    end

    # Check if this is a DM channel
    # @return [Boolean] True if DM
    def dm?
      type == 1
    end

    # Check if this is a group DM
    # @return [Boolean] True if group DM
    def group_dm?
      type == 3
    end

    # Check if this is a category
    # @return [Boolean] True if category
    def category?
      type == 4
    end

    # Check if this is a thread
    # @return [Boolean] True if thread
    def thread?
      type == 10 || type == 11 || type == 12
    end

    # Check if this is a forum channel
    # @return [Boolean] True if forum
    def forum?
      type == 15
    end

    # Check if this is a media channel
    # @return [Boolean] True if media channel
    def media?
      type == 16
    end

    # Check if this is an announcement channel
    # @return [Boolean] True if announcement
    def announcement?
      type == 5
    end

    # Get mention string for the channel
    # @return [String] Channel mention
    def mention
      "<##{id}>"
    end

    # Get the jump URL for this channel
    # @param guild_id [Snowflake, String] Optional guild ID
    # @return [String] Jump URL
    def jump_url(guild_id: nil)
      gid = guild_id || self.guild_id
      "https://discord.com/channels/#{gid}/#{id}"
    end

    # Get last message timestamp
    # @return [Time, nil] Last message time
    def last_message_at
      last_message_id&.timestamp
    end

    # Check if channel is NSFW
    # @return [Boolean] True if NSFW
    def nsfw?
      nsfw
    end

    # Get the category (parent) ID
    # @return [Snowflake, nil] Parent category ID
    def category_id
      parent_id if category?
    end

    # Check if this is a stage channel
    # @return [Boolean] True if stage
    def stage?
      type == 13
    end

    # Get video quality mode name
    # @return [String] Video quality mode
    def video_quality_mode_name
      video_quality_mode == 2 ? 'full' : 'auto'
    end

    # Get auto archive duration in minutes
    # @return [Integer, nil] Auto archive duration
    def auto_archive_duration
      default_auto_archive_duration
    end

    # Check if thread is archived
    # @return [Boolean, nil] True if archived
    def archived?
      thread_metadata&.dig('archived')
    end

    # Get thread archive timestamp
    # @return [Time, nil] Archive timestamp
    def archive_timestamp
      ts = thread_metadata&.dig('archive_timestamp')
      Time.parse(ts) if ts
    end

    # Check if thread is locked
    # @return [Boolean, nil] True if locked
    def locked?
      thread_metadata&.dig('locked')
    end

    # Check if thread is invitable
    # @return [Boolean, nil] True if invitable
    def invitable?
      thread_metadata&.dig('invitable')
    end

    # Get created_at from snowflake
    # @return [Time] Channel creation time
    def created_at
      id.timestamp
    end

    # Get permissions as Permission object
    # @return [Permission, nil] Permissions
    def permission_overwrites
      return nil unless permissions

      Permission.new(permissions.to_i)
    end

    # Check if this is a directory channel
    # @return [Boolean] True if directory
    def directory?
      type == 14
    end
  end
end
