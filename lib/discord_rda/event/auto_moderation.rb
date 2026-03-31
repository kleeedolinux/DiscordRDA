# frozen_string_literal: true

module DiscordRDA
  # Events for Auto Moderation (automod)
  #
  class AutoModerationRuleCreateEvent < Event
    def initialize(data, shard_id:)
      super('AUTO_MODERATION_RULE_CREATE', data, shard_id: shard_id)
    end

    def rule
      @rule ||= AutoModerationRule.new(@data)
    end

    def guild_id
      @data['guild_id']
    end

    def rule_id
      @data['id']
    end

    def name
      @data['name']
    end

    def creator_id
      @data['creator_id']
    end

    def event_type
      @data['event_type']
    end

    def trigger_type
      @data['trigger_type']
    end

    def enabled
      @data['enabled']
    end
  end

  class AutoModerationRuleUpdateEvent < Event
    def initialize(data, shard_id:)
      super('AUTO_MODERATION_RULE_UPDATE', data, shard_id: shard_id)
    end

    def rule
      @rule ||= AutoModerationRule.new(@data)
    end

    def guild_id
      @data['guild_id']
    end

    def rule_id
      @data['id']
    end

    def name
      @data['name']
    end

    def enabled_changed?
      @data.key?('enabled')
    end

    def name_changed?
      @data.key?('name')
    end
  end

  class AutoModerationRuleDeleteEvent < Event
    def initialize(data, shard_id:)
      super('AUTO_MODERATION_RULE_DELETE', data, shard_id: shard_id)
    end

    def rule
      @rule ||= AutoModerationRule.new(@data)
    end

    def guild_id
      @data['guild_id']
    end

    def rule_id
      @data['id']
    end

    def name
      @data['name']
    end
  end

  class AutoModerationActionExecutionEvent < Event
    def initialize(data, shard_id:)
      super('AUTO_MODERATION_ACTION_EXECUTION', data, shard_id: shard_id)
    end

    def guild_id
      @data['guild_id']
    end

    def action
      @data['action']
    end

    def rule_id
      @data['rule_id']
    end

    def rule_trigger_type
      @data['rule_trigger_type']
    end

    def user_id
      @data['user_id']
    end

    def channel_id
      @data['channel_id']
    end

    def message_id
      @data['message_id']
    end

    def alert_system_message_id
      @data['alert_system_message_id']
    end

    def content
      @data['content']
    end

    def matched_keyword
      @data['matched_keyword']
    end

    def matched_content
      @data['matched_content']
    end

    def action_type
      action&.dig('type')
    end

    def block_message?
      action_type == 1
    end

    def send_alert?
      action_type == 2
    end

    def timeout_user?
      action_type == 3
    end

    def keyword_trigger?
      rule_trigger_type == 1
    end

    def spam_trigger?
      rule_trigger_type == 3
    end

    def keyword_preset_trigger?
      rule_trigger_type == 4
    end

    def mention_spam_trigger?
      rule_trigger_type == 5
    end
  end

  # Represents an Auto Moderation rule
  class AutoModerationRule < Entity
    # Event types
    EVENT_TYPES = {
      message_send: 1
    }.freeze

    # Trigger types
    TRIGGER_TYPES = {
      keyword: 1,
      spam: 3,
      keyword_preset: 4,
      mention_spam: 5,
      member_profile: 6
    }.freeze

    # Keyword preset types
    KEYWORD_PRESETS = {
      profanity: 1,
      sexual_content: 2,
      slurs: 3
    }.freeze

    # Action types
    ACTION_TYPES = {
      block_message: 1,
      send_alert_message: 2,
      timeout: 3,
      block_member_interaction: 4
    }.freeze

    attribute :guild_id, type: :snowflake
    attribute :name, type: :string
    attribute :creator_id, type: :snowflake
    attribute :event_type, type: :integer
    attribute :trigger_type, type: :integer
    attribute :exempt_roles, type: :array, default: []
    attribute :exempt_channels, type: :array, default: []
    attribute :enabled, type: :boolean, default: true

    def trigger_metadata
      @raw_data['trigger_metadata'] || {}
    end

    def actions
      @raw_data['actions'] || []
    end

    def keyword_filter
      trigger_metadata['keyword_filter'] || []
    end

    def regex_patterns
      trigger_metadata['regex_patterns'] || []
    end

    def presets
      trigger_metadata['presets'] || []
    end

    def allow_list
      trigger_metadata['allow_list'] || []
    end

    def mention_total_limit
      trigger_metadata['mention_total_limit']
    end

    def mention_raid_protection_enabled
      trigger_metadata['mention_raid_protection_enabled']
    end

    def event_type_name
      EVENT_TYPES.key(event_type) || :unknown
    end

    def trigger_type_name
      TRIGGER_TYPES.key(trigger_type) || :unknown
    end

    def keyword_trigger?
      trigger_type == 1
    end

    def spam_trigger?
      trigger_type == 3
    end

    def keyword_preset_trigger?
      trigger_type == 4
    end

    def mention_spam_trigger?
      trigger_type == 5
    end

    def member_profile_trigger?
      trigger_type == 6
    end

    def block_message_action?
      actions.any? { |a| a['type'] == 1 }
    end

    def send_alert_action?
      actions.any? { |a| a['type'] == 2 }
    end

    def timeout_action?
      actions.any? { |a| a['type'] == 3 }
    end

    def block_member_interaction_action?
      actions.any? { |a| a['type'] == 4 }
    end
  end
end
