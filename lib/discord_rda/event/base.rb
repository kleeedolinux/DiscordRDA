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
      @data = data.each_with_object({}) { |(key, value), hash| hash[key.to_s] = value }.freeze
      @shard_id = shard_id
      @timestamp = Time.now.utc.freeze
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
    }

    class << self
      # Create an event from Gateway data
      # @param event_type [String] Event type
      # @param data [Hash] Event data
      # @param shard_id [Integer] Shard ID
      # @return [Event] Event instance
      def create(event_type, data, shard_id = 0)
        class_name = event_classes[event_type.to_s]

        if class_name && DiscordRDA.const_defined?(class_name, false)
          DiscordRDA.const_get(class_name, false).new(data, shard_id: shard_id)
        else
          Event.new(event_type, data, shard_id: shard_id)
        end
      end

      # Register a custom event class
      # @param event_type [String] Event type
      # @param klass [Class] Event class
      # @return [void]
      def register(event_type, klass)
        event_classes[event_type.to_s] = klass.name.split('::').last
      end

      private

      def event_classes
        @event_classes ||= EVENT_CLASSES.dup
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

    def guild_id
      @data['guild_id']
    end

    def edited?
      true
    end

    def edited_timestamp
      @data['edited_timestamp']
    end

    def author
      @author ||= User.new(@data['author']) if @data['author']
    end

    def member
      return nil unless @data['member']
      @member ||= Member.new(@data['author'].merge('member' => @data['member'], 'guild_id' => guild_id))
    end

    def content
      @data['content']
    end

    def embeds
      @data['embeds'] || []
    end

    def attachments
      @data['attachments'] || []
    end

    def components
      @data['components'] || []
    end

    def mentions
      @data['mentions'] || []
    end

    def mention_roles
      @data['mention_roles'] || []
    end

    def pinned
      @data['pinned']
    end

    def flags
      @data['flags']
    end

    def changed_fields
      @data.keys - %w[id channel_id guild_id]
    end

    def content_changed?
      @data.key?('content')
    end

    def embeds_changed?
      @data.key?('embeds')
    end

    def attachments_changed?
      @data.key?('attachments')
    end

    def components_changed?
      @data.key?('components')
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

    def message
      @message ||= begin
        # Try to reconstruct partial message from available data
        if @data['author'] || @data['content'] || @data['embeds']
          Message.new(@data.merge('id' => message_id, 'deleted' => true))
        else
          nil
        end
      end
    end

    def author
      @author ||= User.new(@data['author']) if @data['author']
    end

    def content
      @data['content']
    end

    def guild?
      !guild_id.nil?
    end

    def dm?
      guild_id.nil?
    end

    def jump_url
      if guild_id
        "https://discord.com/channels/#{guild_id}/#{channel_id}/#{message_id}"
      else
        "https://discord.com/channels/@me/#{channel_id}/#{message_id}"
      end
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

    def messages
      @messages ||= (@data['messages'] || []).map { |m| Message.new(m.merge('deleted' => true)) }
    end

    def author_ids
      messages.map { |m| m.author&.id }.compact.uniq
    end

    def messages_by_author
      messages.group_by { |m| m.author&.id }
    end

    def bulk_delete?
      count > 1
    end

    def jump_url(message_id)
      if guild_id
        "https://discord.com/channels/#{guild_id}/#{channel_id}/#{message_id}"
      else
        "https://discord.com/channels/@me/#{channel_id}/#{message_id}"
      end
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

    def member
      return nil unless @data['member']
      @member ||= Member.new(@data['member'].merge('user' => @data['user'], 'guild_id' => guild_id))
    end

    def emoji
      @emoji ||= Emoji.new(@data['emoji']) if @data['emoji']
    end

    def message_author_id
      @data['message_author_id']
    end

    def burst
      @data['burst'] || false
    end

    def burst_colors
      @data['burst_colors'] || []
    end

    def type
      @data['type']
    end

    def normal?
      type == 0
    end

    def super?
      type == 1
    end

    def guild?
      !guild_id.nil?
    end

    def dm?
      guild_id.nil?
    end

    def animated_emoji?
      emoji&.animated?
    end

    def custom_emoji?
      emoji&.custom?
    end

    def unicode_emoji?
      emoji&.unicode?
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

    def user
      @user ||= User.new(@data['user']) if @data['user']
    end

    def emoji
      @emoji ||= Emoji.new(@data['emoji']) if @data['emoji']
    end

    def burst
      @data['burst'] || false
    end

    def type
      @data['type']
    end

    def normal?
      type == 0
    end

    def super?
      type == 1
    end

    def guild?
      !guild_id.nil?
    end

    def dm?
      guild_id.nil?
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

    def guild?
      !guild_id.nil?
    end

    def dm?
      guild_id.nil?
    end

    def jump_url
      if guild_id
        "https://discord.com/channels/#{guild_id}/#{channel_id}/#{message_id}"
      else
        "https://discord.com/channels/@me/#{channel_id}/#{message_id}"
      end
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

    def guild_id
      @data['guild_id']
    end

    def parent_id
      @data['parent_id']
    end

    def creator_id
      @data['owner_id']
    end
  end

  class ThreadUpdateEvent < Event
    def initialize(data, shard_id:)
      super('THREAD_UPDATE', data, shard_id: shard_id)
    end

    def thread
      @thread ||= Channel.new(@data)
    end

    def guild_id
      @data['guild_id']
    end

    def parent_id
      @data['parent_id']
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

  class ThreadListSyncEvent < Event
    def initialize(data, shard_id:)
      super('THREAD_LIST_SYNC', data, shard_id: shard_id)
    end

    def guild_id
      @data['guild_id']
    end

    def channel_ids
      @data['channel_ids'] || []
    end

    def threads
      @threads ||= (@data['threads'] || []).map { |t| Channel.new(t) }
    end

    def members
      @data['members'] || []
    end

    def thread_count
      threads.length
    end
  end

  class ThreadMemberUpdateEvent < Event
    def initialize(data, shard_id:)
      super('THREAD_MEMBER_UPDATE', data, shard_id: shard_id)
    end

    def thread_id
      @data['id']
    end

    def guild_id
      @data['guild_id']
    end

    def member
      @member ||= @data['member']
    end

    def user_id
      @data['user_id']
    end

    def join_timestamp
      @data['join_timestamp']
    end

    def flags
      @data['flags']
    end
  end

  class ThreadMembersUpdateEvent < Event
    def initialize(data, shard_id:)
      super('THREAD_MEMBERS_UPDATE', data, shard_id: shard_id)
    end

    def thread_id
      @data['id']
    end

    def guild_id
      @data['guild_id']
    end

    def member_count
      @data['member_count']
    end

    def added_members
      @added_members ||= (@data['added_members'] || []).map { |m| Member.new(m.merge('guild_id' => guild_id)) }
    end

    def removed_member_ids
      @data['removed_member_ids'] || []
    end
  end

  class GuildIntegrationsUpdateEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_INTEGRATIONS_UPDATE', data, shard_id: shard_id)
    end

    def guild_id
      @data['guild_id'] ? Snowflake.new(@data['guild_id']) : nil
    end
  end

  class PresenceUpdateEvent < Event
    def initialize(data, shard_id:)
      super('PRESENCE_UPDATE', data, shard_id: shard_id)
    end

    def presence
      Presence.new(@data)
    end

    def user
      presence.user
    end

    def guild_id
      presence.guild_id
    end

    def status
      presence.status
    end

    def activities
      presence.activities
    end

    def client_status
      presence.client_status
    end
  end

  class TypingStartEvent < Event
    def initialize(data, shard_id:)
      super('TYPING_START', data, shard_id: shard_id)
    end

    def channel_id
      @data['channel_id'] ? Snowflake.new(@data['channel_id']) : nil
    end

    def guild_id
      @data['guild_id'] ? Snowflake.new(@data['guild_id']) : nil
    end

    def user_id
      @data['user_id'] ? Snowflake.new(@data['user_id']) : nil
    end

    def member
      return nil unless @data['member']

      Member.new(@data['member'].merge('guild_id' => @data['guild_id']))
    end

    def started_at
      Time.at(@data['timestamp'].to_i).utc if @data['timestamp']
    end

    def guild?
      !guild_id.nil?
    end
  end

  class UserUpdateEvent < Event
    def initialize(data, shard_id:)
      super('USER_UPDATE', data, shard_id: shard_id)
    end

    def user
      User.new(@data)
    end
  end

  class VoiceStateUpdateEvent < Event
    def initialize(data, shard_id:)
      super('VOICE_STATE_UPDATE', data, shard_id: shard_id)
    end

    def voice_state
      VoiceState.new(@data)
    end

    def guild_id
      voice_state.guild_id
    end

    def channel_id
      voice_state.channel_id
    end

    def user_id
      voice_state.user_id
    end

    def member
      voice_state.member
    end

    def session_id
      voice_state.session_id
    end
  end

  class VoiceServerUpdateEvent < Event
    def initialize(data, shard_id:)
      super('VOICE_SERVER_UPDATE', data, shard_id: shard_id)
    end

    def server
      VoiceServer.new(@data)
    end

    def guild_id
      server.guild_id
    end

    def token
      server.token
    end

    def endpoint
      server.endpoint
    end
  end

  class WebhooksUpdateEvent < Event
    def initialize(data, shard_id:)
      super('WEBHOOKS_UPDATE', data, shard_id: shard_id)
    end

    def guild_id
      @data['guild_id'] ? Snowflake.new(@data['guild_id']) : nil
    end

    def channel_id
      @data['channel_id'] ? Snowflake.new(@data['channel_id']) : nil
    end
  end

  class StageInstanceCreateEvent < Event
    def initialize(data, shard_id:)
      super('STAGE_INSTANCE_CREATE', data, shard_id: shard_id)
    end

    def stage_instance
      StageInstance.new(@data)
    end

    def guild_id
      stage_instance.guild_id
    end

    def channel_id
      stage_instance.channel_id
    end
  end

  class StageInstanceUpdateEvent < Event
    def initialize(data, shard_id:)
      super('STAGE_INSTANCE_UPDATE', data, shard_id: shard_id)
    end

    def stage_instance
      StageInstance.new(@data)
    end

    def guild_id
      stage_instance.guild_id
    end

    def channel_id
      stage_instance.channel_id
    end
  end

  class StageInstanceDeleteEvent < Event
    def initialize(data, shard_id:)
      super('STAGE_INSTANCE_DELETE', data, shard_id: shard_id)
    end

    def stage_instance
      StageInstance.new(@data)
    end

    def guild_id
      stage_instance.guild_id
    end

    def channel_id
      stage_instance.channel_id
    end
  end

  class GuildAuditLogEntryCreateEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_AUDIT_LOG_ENTRY_CREATE', data, shard_id: shard_id)
    end

    def entry
      AuditLogEntry.new(@data)
    end

    def guild_id
      @data['guild_id'] ? Snowflake.new(@data['guild_id']) : nil
    end
  end

  class EntitlementCreateEvent < Event
    def initialize(data, shard_id:)
      super('ENTITLEMENT_CREATE', data, shard_id: shard_id)
    end

    def entitlement
      Entitlement.new(@data)
    end
  end

  class EntitlementUpdateEvent < Event
    def initialize(data, shard_id:)
      super('ENTITLEMENT_UPDATE', data, shard_id: shard_id)
    end

    def entitlement
      Entitlement.new(@data)
    end
  end

  class EntitlementDeleteEvent < Event
    def initialize(data, shard_id:)
      super('ENTITLEMENT_DELETE', data, shard_id: shard_id)
    end

    def entitlement
      Entitlement.new(@data)
    end
  end
end
