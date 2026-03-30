# frozen_string_literal: true

require 'cgi'
require_relative 'message_builder'

module DiscordRDA
  # Represents a Discord message.
  # Messages can contain text, embeds, attachments, and more.
  #
  class Message < Entity
    # Class-level API client for making REST requests
    # @return [RestClient, ScalableRestClient, nil] The REST client to use
    class << self
      attr_accessor :api
    end

    # Message types
    TYPES = {
      default: 0,
      recipient_add: 1,
      recipient_remove: 2,
      call: 3,
      channel_name_change: 4,
      channel_icon_change: 5,
      channel_pinned_message: 6,
      user_join: 7,
      guild_boost: 8,
      guild_boost_tier_1: 9,
      guild_boost_tier_2: 10,
      guild_boost_tier_3: 11,
      channel_follow_add: 12,
      guild_discovery_disqualified: 14,
      guild_discovery_requalified: 15,
      guild_discovery_grace_period_initial_warning: 16,
      guild_discovery_grace_period_final_warning: 17,
      thread_created: 18,
      reply: 19,
      chat_input_command: 20,
      thread_starter_message: 21,
      guild_invite_reminder: 22,
      context_menu_command: 23,
      auto_moderation_action: 24,
      role_subscription_purchase: 25,
      interaction_premium_upsell: 26,
      stage_start: 27,
      stage_end: 28,
      stage_speaker: 29,
      stage_topic: 31,
      guild_application_premium_subscription: 32,
      guild_incident_alert_mode_enabled: 36,
      guild_incident_alert_mode_disabled: 37,
      guild_incident_report_raid: 38,
      guild_incident_report_false_alarm: 39,
      purchase_notification: 44,
      poll_result: 46
    }.freeze

    attribute :channel_id, type: :snowflake
    attribute :author, type: :hash
    attribute :content, type: :string, default: ''
    attribute :timestamp, type: :time
    attribute :edited_timestamp, type: :time
    attribute :tts, type: :boolean, default: false
    attribute :mention_everyone, type: :boolean, default: false
    attribute :mentions, type: :array, default: []
    attribute :mention_roles, type: :array, default: []
    attribute :mention_channels, type: :array, default: []
    attribute :attachments, type: :array, default: []
    attribute :embeds, type: :array, default: []
    attribute :reactions, type: :array, default: []
    attribute :nonce, type: :string
    attribute :pinned, type: :boolean, default: false
    attribute :webhook_id, type: :snowflake
    attribute :type, type: :integer, default: 0
    attribute :activity, type: :hash
    attribute :application, type: :hash
    attribute :application_id, type: :snowflake
    attribute :message_reference, type: :hash
    attribute :flags, type: :integer, default: 0
    attribute :referenced_message, type: :hash
    attribute :interaction_metadata, type: :hash
    attribute :interaction, type: :hash
    attribute :api, type: :hash
    attribute :components, type: :array, default: []
    attribute :sticker_items, type: :array, default: []
    attribute :stickers, type: :array, default: []
    attribute :position, type: :integer
    attribute :role_subscription_data, type: :hash
    attribute :resolved, type: :hash
    attribute :poll, type: :hash
    attribute :call, type: :hash

    # Get message type as symbol
    # @return [Symbol] Message type
    def message_type
      TYPES.key(type) || :unknown
    end

    # Get the author as a User entity
    # @return [User, Member] Author
    def author
      return nil unless @raw_data['author']

      if @raw_data['member']
        Member.new(@raw_data['author'].merge('member' => @raw_data['member'], 'guild_id' => @raw_data['guild_id']))
      else
        User.new(@raw_data['author'])
      end
    end

    # Get mentioned users
    # @return [Array<User>] Mentioned users
    def mentioned_users
      (@raw_data['mentions'] || []).map { |m| User.new(m) }
    end

    # Get mentioned roles as snowflakes
    # @return [Array<Snowflake>] Mentioned role IDs
    def mentioned_roles
      (@raw_data['mention_roles'] || []).map { |r| Snowflake.new(r) }
    end

    # Get mentioned channels
    # @return [Array<Channel>] Mentioned channels
    def mentioned_channels
      (@raw_data['mention_channels'] || []).map { |c| Channel.new(c) }
    end

    # Get attachments
    # @return [Array<Attachment>] Attachments
    def attachments
      (@raw_data['attachments'] || []).map { |a| Attachment.new(a) }
    end

    # Get embeds
    # @return [Array<Embed>] Embeds
    def embeds
      (@raw_data['embeds'] || []).map { |e| Embed.new(e) }
    end

    # Get reactions
    # @return [Array<Reaction>] Reactions
    def reactions
      (@raw_data['reactions'] || []).map { |r| Reaction.new(r) }
    end

    # Check if message is TTS
    # @return [Boolean] True if TTS
    def tts?
      tts
    end

    # Check if message mentions everyone
    # @return [Boolean] True if mentions everyone
    def mention_everyone?
      mention_everyone
    end

    # Check if message is pinned
    # @return [Boolean] True if pinned
    def pinned?
      pinned
    end

    # Check if message was edited
    # @return [Boolean] True if edited
    def edited?
      !edited_timestamp.nil?
    end

    # Get edit timestamp
    # @return [Time, nil] Edit time
    def edited_at
      edited_timestamp
    end

    # Check if this is a reply to another message
    # @return [Boolean] True if reply
    def reply?
      type == 19 || !message_reference.nil?
    end

    # Get the referenced (replied to) message
    # @return [Message, nil] Referenced message
    def referenced_message
      ref = @raw_data['referenced_message']
      Message.new(ref) if ref
    end

    # Get the message reference data
    # @return [Hash, nil] Message reference
    def message_reference
      @raw_data['message_reference']
    end

    # Get the jump URL for this message
    # @return [String] Jump URL
    def jump_url
      guild_id = @raw_data['guild_id']
      if guild_id
        "https://discord.com/channels/#{guild_id}/#{channel_id}/#{id}"
      else
        "https://discord.com/channels/@me/#{channel_id}/#{id}"
      end
    end

    # Check if message is from a webhook
    # @return [Boolean] True if webhook message
    def webhook?
      !webhook_id.nil?
    end

    # Check if message has embeds
    # @return [Boolean] True if has embeds
    def has_embeds?
      embeds.any?
    end

    # Check if message has attachments
    # @return [Boolean] True if has attachments
    def has_attachments?
      attachments.any?
    end

    # Check if message has reactions
    # @return [Boolean] True if has reactions
    def has_reactions?
      reactions.any?
    end

    # Get total reaction count
    # @return [Integer] Total reactions
    def reaction_count
      reactions.sum(&:count)
    end

    # Check if message is a system message
    # @return [Boolean] True if system message
    def system?
      type != 0 && type != 19 && type != 20 && type != 23
    end

    # Check if message was deleted
    # @return [Boolean] True if deleted (not present in data)
    def deleted?
      @raw_data['deleted'] || false
    end

    # Check if message has components (buttons, select menus)
    # @return [Boolean] True if has components
    def has_components?
      components.any?
    end

    # Check if message has a poll
    # @return [Boolean] True if has poll
    def has_poll?
      !poll.nil?
    end

    # Get sticker items
    # @return [Array<Sticker>] Sticker items
    def stickers
      (@raw_data['sticker_items'] || @raw_data['stickers'] || []).map { |s| Sticker.new(s) }
    end

    # Get message flags
    # @return [MessageFlags] Flags object
    def message_flags
      MessageFlags.new(flags)
    end

    # Get thread associated with this message
    # @return [Channel, nil] Thread if created from this message
    def thread
      return nil unless @raw_data['thread']

      Channel.new(@raw_data['thread'])
    end

    # Get application
    # @return [Application, nil] Application
    def application
      return nil unless @raw_data['application']

      Application.new(@raw_data['application'])
    end

    # Get resolved data for interactions
    # @return [ResolvedData, nil] Resolved data
    def resolved_data
      return nil unless @raw_data['resolved']

      ResolvedData.new(@raw_data['resolved'])
    end

    # Get position in thread
    # @return [Integer, nil] Position
    def position
      @raw_data['position']
    end

    # Respond to this message (send reply)
    # @param content [String] Message content
    # @param options [Hash] Additional options (embeds, components, etc.)
    # @yieldparam builder [MessageBuilder] Optional builder block
    # @return [Message] The sent message
    def respond(content = nil, **options, &block)
      raise 'API client not configured. Call Bot#initialize first.' unless self.class.api

      payload = { content: content }.merge(options).compact
      payload[:message_reference] = {
        message_id: id.to_s,
        channel_id: channel_id.to_s,
        guild_id: @raw_data['guild_id'],
        fail_if_not_exists: false
      }

      # Execute builder block if given
      if block
        builder = MessageBuilder.new(payload)
        block.call(builder)
        payload = builder.to_h
      end

      data = self.class.api.post("/channels/#{channel_id}/messages", body: payload)
      Message.new(data)
    end

    # React to this message with an emoji
    # @param emoji [String, Emoji] Emoji to react with (can be unicode emoji or emoji ID string)
    # @return [void]
    def react(emoji)
      raise 'API client not configured. Call Bot#initialize first.' unless self.class.api

      emoji_string = emoji.respond_to?(:id) ? "#{emoji.name}:#{emoji.id}" : emoji.to_s
      emoji_encoded = CGI.escape(emoji_string)

      self.class.api.put("/channels/#{channel_id}/messages/#{id}/reactions/#{emoji_encoded}/@me")
    end

    # Delete this message
    # @param reason [String] Audit log reason
    # @return [void]
    def delete(reason: nil)
      raise 'API client not configured. Call Bot#initialize first.' unless self.class.api

      headers = {}
      headers['X-Audit-Log-Reason'] = CGI.escape(reason) if reason

      self.class.api.delete("/channels/#{channel_id}/messages/#{id}", headers: headers)
    end

    # Pin this message
    # @param reason [String] Audit log reason
    # @return [void]
    def pin(reason: nil)
      raise 'API client not configured. Call Bot#initialize first.' unless self.class.api

      headers = {}
      headers['X-Audit-Log-Reason'] = CGI.escape(reason) if reason

      self.class.api.put("/channels/#{channel_id}/pins/#{id}", headers: headers)
    end

    # Unpin this message
    # @param reason [String] Audit log reason
    # @return [void]
    def unpin(reason: nil)
      raise 'API client not configured. Call Bot#initialize first.' unless self.class.api

      headers = {}
      headers['X-Audit-Log-Reason'] = CGI.escape(reason) if reason

      self.class.api.delete("/channels/#{channel_id}/pins/#{id}", headers: headers)
    end

    # Edit this message
    # @param content [String] New content
    # @param options [Hash] Additional options (embeds, components, etc.)
    # @yieldparam builder [MessageBuilder] Optional builder block
    # @return [Message] The edited message
    def edit(content = nil, **options, &block)
      raise 'API client not configured. Call Bot#initialize first.' unless self.class.api

      payload = { content: content }.merge(options).compact

      # Execute builder block if given
      if block
        builder = MessageBuilder.new(payload)
        block.call(builder)
        payload = builder.to_h
      end

      data = self.class.api.patch("/channels/#{channel_id}/messages/#{id}", body: payload)
      Message.new(data)
    end

    # Get creation time
    # @return [Time] Message creation time
    def created_at
      timestamp
    end
  end
end
