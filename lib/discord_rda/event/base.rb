# frozen_string_literal: true

module DiscordRDA
  # Base event class for all Discord events.
  # Events are immutable data objects.
  #
  class Event
    # @return [String] Event type
    attr_reader :type

    # @return [Integer] Shard ID where event originated
    attr_reader :shard_id

    # @return [Hash] Raw event data
    attr_reader :data

    # @return [Time] Event timestamp
    attr_reader :timestamp

    # Initialize event
    # @param type [String] Event type
    # @param data [Hash] Raw data
    # @param shard_id [Integer] Shard ID
    def initialize(type, data, shard_id: 0)
      @type = type.to_s
      @data = data.freeze
      @shard_id = shard_id
      @timestamp = Time.now.utc.freeze
      freeze
    end

    # Get creation time from data if available
    # @return [Time, nil] Creation time
    def created_at
      return nil unless @data['id']

      Snowflake.new(@data['id']).timestamp
    end

    # Convert to hash
    # @return [Hash] Event as hash
    def to_h
      {
        type: @type,
        shard_id: @shard_id,
        timestamp: @timestamp.iso8601,
        data: @data
      }
    end

    # Inspect
    # @return [String] Inspect string
    def inspect
      "#<#{self.class.name} type=#{@type} shard=#{@shard_id}>"
    end
  end

  # Handler interface for events
  class EventHandler
    # @return [Proc] Handler block
    attr_reader :block

    # Initialize handler
    # @param block [Proc] Handler block
    def initialize(block)
      @block = block
    end

    # Call the handler
    # @param event [Event] Event to handle
    # @return [Object] Handler result
    def call(event)
      @block.call(event)
    end

    # Check if handler responds to event
    # @param event [Event] Event to check
    # @return [Boolean] True if can handle
    def handles?(event)
      true
    end
  end

  # Middleware for intercepting events
  class Middleware
    # Call middleware
    # @param event [Event] Event being processed
    # @yield Call next in chain
    def call(event)
      yield
    end
  end

  # Factory for creating events from Gateway payloads
  module EventFactory
    # Event type to class mapping
    EVENT_CLASSES = {
      'READY' => 'ReadyEvent',
      'RESUMED' => 'ResumedEvent',
      'CHANNEL_CREATE' => 'ChannelCreateEvent',
      'CHANNEL_UPDATE' => 'ChannelUpdateEvent',
      'CHANNEL_DELETE' => 'ChannelDeleteEvent',
      'CHANNEL_PINS_UPDATE' => 'ChannelPinsUpdateEvent',
      'GUILD_CREATE' => 'GuildCreateEvent',
      'GUILD_UPDATE' => 'GuildUpdateEvent',
      'GUILD_DELETE' => 'GuildDeleteEvent',
      'GUILD_BAN_ADD' => 'GuildBanAddEvent',
      'GUILD_BAN_REMOVE' => 'GuildBanRemoveEvent',
      'GUILD_EMOJIS_UPDATE' => 'GuildEmojisUpdateEvent',
      'GUILD_INTEGRATIONS_UPDATE' => 'GuildIntegrationsUpdateEvent',
      'GUILD_MEMBER_ADD' => 'GuildMemberAddEvent',
      'GUILD_MEMBER_REMOVE' => 'GuildMemberRemoveEvent',
      'GUILD_MEMBER_UPDATE' => 'GuildMemberUpdateEvent',
      'GUILD_MEMBERS_CHUNK' => 'GuildMembersChunkEvent',
      'GUILD_ROLE_CREATE' => 'GuildRoleCreateEvent',
      'GUILD_ROLE_UPDATE' => 'GuildRoleUpdateEvent',
      'GUILD_ROLE_DELETE' => 'GuildRoleDeleteEvent',
      'MESSAGE_CREATE' => 'MessageCreateEvent',
      'MESSAGE_UPDATE' => 'MessageUpdateEvent',
      'MESSAGE_DELETE' => 'MessageDeleteEvent',
      'MESSAGE_DELETE_BULK' => 'MessageDeleteBulkEvent',
      'MESSAGE_REACTION_ADD' => 'MessageReactionAddEvent',
      'MESSAGE_REACTION_REMOVE' => 'MessageReactionRemoveEvent',
      'MESSAGE_REACTION_REMOVE_ALL' => 'MessageReactionRemoveAllEvent',
      'MESSAGE_REACTION_REMOVE_EMOJI' => 'MessageReactionRemoveEmojiEvent',
      'PRESENCE_UPDATE' => 'PresenceUpdateEvent',
      'TYPING_START' => 'TypingStartEvent',
      'USER_UPDATE' => 'UserUpdateEvent',
      'VOICE_STATE_UPDATE' => 'VoiceStateUpdateEvent',
      'VOICE_SERVER_UPDATE' => 'VoiceServerUpdateEvent',
      'WEBHOOKS_UPDATE' => 'WebhooksUpdateEvent',
      'INTERACTION_CREATE' => 'InteractionCreateEvent',
      'STAGE_INSTANCE_CREATE' => 'StageInstanceCreateEvent',
      'STAGE_INSTANCE_UPDATE' => 'StageInstanceUpdateEvent',
      'STAGE_INSTANCE_DELETE' => 'StageInstanceDeleteEvent',
      'THREAD_CREATE' => 'ThreadCreateEvent',
      'THREAD_UPDATE' => 'ThreadUpdateEvent',
      'THREAD_DELETE' => 'ThreadDeleteEvent',
      'THREAD_LIST_SYNC' => 'ThreadListSyncEvent',
      'THREAD_MEMBER_UPDATE' => 'ThreadMemberUpdateEvent',
      'THREAD_MEMBERS_UPDATE' => 'ThreadMembersUpdateEvent',
      'GUILD_SCHEDULED_EVENT_CREATE' => 'GuildScheduledEventCreateEvent',
      'GUILD_SCHEDULED_EVENT_UPDATE' => 'GuildScheduledEventUpdateEvent',
      'GUILD_SCHEDULED_EVENT_DELETE' => 'GuildScheduledEventDeleteEvent',
      'GUILD_SCHEDULED_EVENT_USER_ADD' => 'GuildScheduledEventUserAddEvent',
      'GUILD_SCHEDULED_EVENT_USER_REMOVE' => 'GuildScheduledEventUserRemoveEvent',
      'AUTO_MODERATION_RULE_CREATE' => 'AutoModerationRuleCreateEvent',
      'AUTO_MODERATION_RULE_UPDATE' => 'AutoModerationRuleUpdateEvent',
      'AUTO_MODERATION_RULE_DELETE' => 'AutoModerationRuleDeleteEvent',
      'AUTO_MODERATION_ACTION_EXECUTION' => 'AutoModerationActionExecutionEvent',
      'GUILD_AUDIT_LOG_ENTRY_CREATE' => 'GuildAuditLogEntryCreateEvent',
      'ENTITLEMENT_CREATE' => 'EntitlementCreateEvent',
      'ENTITLEMENT_UPDATE' => 'EntitlementUpdateEvent',
      'ENTITLEMENT_DELETE' => 'EntitlementDeleteEvent'
    }.freeze

    class << self
      # Create an event from Gateway data
      # @param event_type [String] Event type
      # @param data [Hash] Event data
      # @param shard_id [Integer] Shard ID
      # @return [Event] Event instance
      def create(event_type, data, shard_id = 0)
        class_name = EVENT_CLASSES[event_type]

        if class_name && Event.const_defined?(class_name)
          Event.const_get(class_name).new(data, shard_id: shard_id)
        else
          Event.new(event_type, data, shard_id: shard_id)
        end
      end

      # Register a custom event class
      # @param event_type [String] Event type
      # @param klass [Class] Event class
      # @return [void]
      def register(event_type, klass)
        EVENT_CLASSES[event_type] = klass.name
      end
    end
  end

  # Specific event classes
  class ReadyEvent < Event
    def initialize(data, shard_id:)
      super('READY', data, shard_id: shard_id)
    end

    def guilds
      @data['guilds'] || []
    end

    def user
      @user ||= User.new(@data['user']) if @data['user']
    end

    def session_id
      @data['session_id']
    end
  end

  class ResumedEvent < Event
    def initialize(data, shard_id:)
      super('RESUMED', data, shard_id: shard_id)
    end
  end

  class MessageCreateEvent < Event
    def initialize(data, shard_id:)
      super('MESSAGE_CREATE', data, shard_id: shard_id)
    end

    def message
      @message ||= Message.new(@data)
    end

    def author
      message.author
    end

    def channel_id
      message.channel_id
    end

    def guild_id
      @data['guild_id'] ? Snowflake.new(@data['guild_id']) : nil
    end

    def content
      message.content
    end

    def mentions_bot?(bot_id)
      message.mentioned_users.any? { |u| u.id.to_s == bot_id.to_s }
    end
  end

  class GuildCreateEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_CREATE', data, shard_id: shard_id)
    end

    def guild
      @guild ||= Guild.new(@data)
    end

    def available?
      !@data['unavailable']
    end
  end

  class InteractionCreateEvent < Event
    def initialize(data, shard_id:)
      super('INTERACTION_CREATE', data, shard_id: shard_id)
    end

    def interaction
      @interaction ||= Interaction.new(@data)
    end

    def type
      @data['type']
    end

    def command?
      type == 2
    end

    def component?
      type == 3
    end

    def modal_submit?
      type == 5
    end
  end

  # InteractionCreateEvent - uses full Interaction class from interactions module
  class InteractionCreateEvent < Event
    def initialize(data, shard_id:)
      super('INTERACTION_CREATE', data, shard_id: shard_id)
    end

    def interaction
      @interaction ||= Interaction.new(@data)
    end

    def type
      interaction.type
    end

    def command?
      interaction.command?
    end

    def component?
      interaction.component?
    end

    def modal_submit?
      interaction.modal_submit?
    end
  end
end
