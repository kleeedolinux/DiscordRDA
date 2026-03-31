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
      interaction.component?
    end

    def modal_submit?
      interaction.modal_submit?
    end
  end

  # Channel events
  class ChannelCreateEvent < Event
    def initialize(data, shard_id:)
      super('CHANNEL_CREATE', data, shard_id: shard_id)
    end

    def channel
      @channel ||= Channel.new(@data)
    end
  end

  class ChannelUpdateEvent < Event
    def initialize(data, shard_id:)
      super('CHANNEL_UPDATE', data, shard_id: shard_id)
    end

    def channel
      @channel ||= Channel.new(@data)
    end

    def before
      @data['before']
    end

    def after
      channel
    end
  end

  class ChannelDeleteEvent < Event
    def initialize(data, shard_id:)
      super('CHANNEL_DELETE', data, shard_id: shard_id)
    end

    def channel
      @channel ||= Channel.new(@data)
    end
  end

  class ChannelPinsUpdateEvent < Event
    def initialize(data, shard_id:)
      super('CHANNEL_PINS_UPDATE', data, shard_id: shard_id)
    end

    def channel_id
      @data['channel_id']
    end

    def guild_id
      @data['guild_id']
    end

    def last_pin_timestamp
      @data['last_pin_timestamp']
    end
  end

  # Guild events
  class GuildUpdateEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_UPDATE', data, shard_id: shard_id)
    end

    def guild
      @guild ||= Guild.new(@data)
    end
  end

  class GuildDeleteEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_DELETE', data, shard_id: shard_id)
    end

    def guild_id
      @data['id']
    end

    def unavailable?
      @data['unavailable'] || false
    end
  end

  # Member events
  class GuildMemberAddEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_MEMBER_ADD', data, shard_id: shard_id)
    end

    def member
      @member ||= Member.new(@data)
    end

    def guild_id
      @data['guild_id']
    end
  end

  class GuildMemberRemoveEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_MEMBER_REMOVE', data, shard_id: shard_id)
    end

    def user
      @user ||= User.new(@data['user'])
    end

    def guild_id
      @data['guild_id']
    end
  end

  class GuildMemberUpdateEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_MEMBER_UPDATE', data, shard_id: shard_id)
    end

    def member
      @member ||= Member.new(@data)
    end

    def guild_id
      @data['guild_id']
    end

    def roles
      @data['roles'] || []
    end

    def nick
      @data['nick']
    end
  end

  # Role events
  class GuildRoleCreateEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_ROLE_CREATE', data, shard_id: shard_id)
    end

    def role
      @role ||= Role.new(@data['role'].merge('guild_id' => @data['guild_id']))
    end

    def guild_id
      @data['guild_id']
    end
  end

  class GuildRoleUpdateEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_ROLE_UPDATE', data, shard_id: shard_id)
    end

    def role
      @role ||= Role.new(@data['role'].merge('guild_id' => @data['guild_id']))
    end

    def guild_id
      @data['guild_id']
    end
  end

  class GuildRoleDeleteEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_ROLE_DELETE', data, shard_id: shard_id)
    end

    def role_id
      @data['role_id']
    end

    def guild_id
      @data['guild_id']
    end
  end

  # Message events
  class MessageUpdateEvent < Event
    def initialize(data, shard_id:)
      super('MESSAGE_UPDATE', data, shard_id: shard_id)
    end

    def message
      @message ||= Message.new(@data)
    end

    def id
      @data['id']
    end

    def channel_id
      @data['channel_id']
    end

    def edited?
      true
    end
  end

  class MessageDeleteEvent < Event
    def initialize(data, shard_id:)
      super('MESSAGE_DELETE', data, shard_id: shard_id)
    end

    def message_id
      @data['id']
    end

    def channel_id
      @data['channel_id']
    end

    def guild_id
      @data['guild_id']
    end
  end

  class MessageDeleteBulkEvent < Event
    def initialize(data, shard_id:)
      super('MESSAGE_DELETE_BULK', data, shard_id: shard_id)
    end

    def message_ids
      @data['ids'] || []
    end

    def channel_id
      @data['channel_id']
    end

    def guild_id
      @data['guild_id']
    end

    def count
      message_ids.length
    end
  end

  # Reaction events
  class MessageReactionAddEvent < Event
    def initialize(data, shard_id:)
      super('MESSAGE_REACTION_ADD', data, shard_id: shard_id)
    end

    def message_id
      @data['message_id']
    end

    def channel_id
      @data['channel_id']
    end

    def guild_id
      @data['guild_id']
    end

    def user
      @user ||= User.new(@data['member'] || @data['user']) if @data['member'] || @data['user']
    end

    def emoji
      @emoji ||= Emoji.new(@data['emoji']) if @data['emoji']
    end
  end

  class MessageReactionRemoveEvent < Event
    def initialize(data, shard_id:)
      super('MESSAGE_REACTION_REMOVE', data, shard_id: shard_id)
    end

    def message_id
      @data['message_id']
    end

    def channel_id
      @data['channel_id']
    end

    def guild_id
      @data['guild_id']
    end

    def user_id
      @data['user_id']
    end

    def emoji
      @emoji ||= Emoji.new(@data['emoji']) if @data['emoji']
    end
  end

  class MessageReactionRemoveAllEvent < Event
    def initialize(data, shard_id:)
      super('MESSAGE_REACTION_REMOVE_ALL', data, shard_id: shard_id)
    end

    def message_id
      @data['message_id']
    end

    def channel_id
      @data['channel_id']
    end

    def guild_id
      @data['guild_id']
    end
  end

  # Ban events
  class GuildBanAddEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_BAN_ADD', data, shard_id: shard_id)
    end

    def user
      @user ||= User.new(@data['user'])
    end

    def guild_id
      @data['guild_id']
    end
  end

  class GuildBanRemoveEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_BAN_REMOVE', data, shard_id: shard_id)
    end

    def user
      @user ||= User.new(@data['user'])
    end

    def guild_id
      @data['guild_id']
    end
  end

  # Thread events
  class ThreadCreateEvent < Event
    def initialize(data, shard_id:)
      super('THREAD_CREATE', data, shard_id: shard_id)
    end

    def thread
      @thread ||= Channel.new(@data)
    end

    def newly_created?
      @data['newly_created'] || false
    end
  end

  class ThreadUpdateEvent < Event
    def initialize(data, shard_id:)
      super('THREAD_UPDATE', data, shard_id: shard_id)
    end

    def thread
      @thread ||= Channel.new(@data)
    end
  end

  class ThreadDeleteEvent < Event
    def initialize(data, shard_id:)
      super('THREAD_DELETE', data, shard_id: shard_id)
    end

    def thread_id
      @data['id']
    end

    def channel_id
      @data['parent_id']
    end

    def guild_id
      @data['guild_id']
    end

    def type
      @data['type']
    end
  end
end
