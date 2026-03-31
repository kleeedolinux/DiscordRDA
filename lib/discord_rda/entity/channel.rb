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

    # Class-level API client for REST operations
    class << self
      attr_accessor :api
    end

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

    # Get slowmode delay in seconds
    # @return [Integer] Rate limit per user
    def slowmode_delay
      rate_limit_per_user || 0
    end

    # Check if slowmode is enabled
    # @return [Boolean] True if slowmode enabled
    def slowmode?
      rate_limit_per_user.to_i > 0
    end

    # Check if channel is synced with category permissions
    # @return [Boolean, nil] True if synced
    def synced?
      @raw_data['parent_id'] && @raw_data['permission_overwrites']&.empty?
    end

    # Get mention string for the channel with type indicator
    # @return [String] Channel mention with '#' prefix for text channels
    def mention_with_prefix
      text? ? "<##{id}>" : mention
    end

    # Get formatted name with type indicator
    # @return [String] Formatted name
    def display_name
      case type
      when 0, 5 then "# #{name}"
      when 2, 13 then "🔊 #{name}"
      when 4 then "📁 #{name}"
      else name
      end
    end

    # Check if the channel is considered active (has recent messages)
    # @return [Boolean] True if active
    def active?
      return false unless last_message_id
      last_message_at > Time.now - 86400 # Active within last 24 hours
    end

    # Get the age of the last message
    # @return [Float, nil] Seconds since last message
    def last_message_age
      return nil unless last_message_at
      Time.now - last_message_at
    end

    # Check if this is a news/announcement channel
    # @return [Boolean] True if news channel
    def news?
      type == 5
    end

    # Get the default auto archive duration in days
    # @return [Integer] Days
    def auto_archive_days
      (default_auto_archive_duration || 4320) / 1440 # Convert minutes to days, default 3 days
    end

    # Fetch messages from the channel with pagination support
    # @param limit [Integer] Number of messages (1-100, default 50)
    # @param before [String, Snowflake] Get messages before this message ID
    # @param after [String, Snowflake] Get messages after this message ID
    # @param around [String, Snowflake] Get messages around this message ID (returns 25 before + 25 after)
    # @return [Array<Message>] Messages
    def fetch_messages(limit: 50, before: nil, after: nil, around: nil)
      return [] unless self.class.api

      params = { limit: limit }
      params[:before] = before.to_s if before
      params[:after] = after.to_s if after
      params[:around] = around.to_s if around

      data = self.class.api.get("/channels/#{id}/messages", params: params)
      data.map { |m| Message.new(m) }
    end

    # Fetch all messages from the channel with automatic pagination
    # @param max [Integer] Maximum messages to fetch (nil for all)
    # @param batch_size [Integer] Messages per request (1-100)
    # @param direction [Symbol] :backwards (older first) or :forwards (newer first)
    # @yield [Message] Optional block called for each message
    # @return [Array<Message>] All fetched messages
    def fetch_all_messages(max: nil, batch_size: 100, direction: :backwards)
      return [] unless self.class.api

      messages = []
      last_id = nil

      loop do
        batch = if direction == :forwards
                  fetch_messages(limit: batch_size, after: last_id)
                else
                  fetch_messages(limit: batch_size, before: last_id)
                end

        break if batch.empty?

        batch.each do |message|
          messages << message
          yield message if block_given?

          return messages if max && messages.length >= max
        end

        last_id = direction == :forwards ? batch.last.id : batch.last.id

        # Stop if we got fewer messages than requested (reached the end)
        break if batch.length < batch_size
      end

      messages
    end

    # Create an iterator for fetching messages
    # @param batch_size [Integer] Messages per request (1-100)
    # @param direction [Symbol] :backwards (older first) or :forwards (newer first)
    # @return [MessageIterator] Iterator instance
    def messages_iterator(batch_size: 100, direction: :backwards)
      MessageIterator.new(self, batch_size: batch_size, direction: direction)
    end

    # Search for messages by content (client-side filtering)
    # Note: Discord API doesn't support server-side message search, this fetches and filters
    # @param content [String] Content to search for
    # @param author_id [String] Filter by author ID
    # @param limit [Integer] Maximum messages to search
    # @return [Array<Message>] Matching messages
    def search_messages(content: nil, author_id: nil, limit: 1000)
      return [] unless self.class.api

      results = []

      fetch_all_messages(max: limit) do |message|
        next if content && !message.content.to_s.downcase.include?(content.downcase)
        next if author_id && message.author&.id.to_s != author_id.to_s

        results << message
      end

      results
    end
  end

  # Iterator for paginating through channel messages
  class MessageIterator
    include Enumerable

    # @return [Channel] Channel being iterated
    attr_reader :channel

    # @return [Integer] Messages per batch
    attr_reader :batch_size

    # @return [Symbol] Direction (:backwards or :forwards)
    attr_reader :direction

    # Initialize iterator
    # @param channel [Channel] Channel to iterate
    # @param batch_size [Integer] Messages per batch
    # @param direction [Symbol] :backwards (older first) or :forwards (newer first)
    def initialize(channel, batch_size: 100, direction: :backwards)
      @channel = channel
      @batch_size = batch_size
      @direction = direction
      @last_id = nil
      @buffer = []
      @exhausted = false
    end

    # Get next message
    # @return [Message, nil] Next message or nil if exhausted
    def next
      fill_buffer if @buffer.empty? && !@exhausted

      @buffer.shift
    end

    # Check if there are more messages
    # @return [Boolean] True if more messages available
    def more?
      !@exhausted || !@buffer.empty?
    end

    # Iterate over all messages
    # @yield [Message]
    def each
      return to_enum unless block_given?

      loop do
        message = self.next
        break unless message

        yield message
      end
    end

    # Reset the iterator
    # @return [self]
    def reset
      @last_id = nil
      @buffer = []
      @exhausted = false
      self
    end

    private

    def fill_buffer
      return if @exhausted

      batch = if @direction == :forwards
                @channel.fetch_messages(limit: @batch_size, after: @last_id)
              else
                @channel.fetch_messages(limit: @batch_size, before: @last_id)
              end

      if batch.empty?
        @exhausted = true
      else
        @buffer = batch
        @last_id = @direction == :forwards ? batch.last.id : batch.last.id
        @exhausted = true if batch.length < @batch_size
      end
    end
  end
end
