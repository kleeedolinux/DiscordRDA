# frozen_string_literal: true

module DiscordRDA
  # Represents role tags from the tags field.
  #
  class RoleTags
    # @return [Hash] Raw tag data
    attr_reader :data

    # Initialize role tags
    # @param data [Hash] Tag data
    def initialize(data)
      @data = data || {}
    end

    # Check if role is for a bot
    # @return [Boolean] True if bot role
    def bot?
      @data.key?('bot_id')
    end

    # Get bot ID if bot role
    # @return [Snowflake, nil] Bot ID
    def bot_id
      @data['bot_id'] ? Snowflake.new(@data['bot_id']) : nil
    end

    # Check if role is for an integration
    # @return [Boolean] True if integration role
    def integration?
      @data.key?('integration_id')
    end

    # Get integration ID if integration role
    # @return [Snowflake, nil] Integration ID
    def integration_id
      @data['integration_id'] ? Snowflake.new(@data['integration_id']) : nil
    end

    # Check if role is the premium subscriber role
    # @return [Boolean] True if premium subscriber role
    def premium_subscriber?
      @data.key?('premium_subscriber') && @data['premium_subscriber'].nil?
    end

    # Check if role is for a subscription listing
    # @return [Boolean] True if subscription listing
    def subscription_listing?
      @data.key?('subscription_listing_id')
    end

    # Get subscription listing ID
    # @return [Snowflake, nil] Subscription listing ID
    def subscription_listing_id
      @data['subscription_listing_id'] ? Snowflake.new(@data['subscription_listing_id']) : nil
    end

    # Check if role is available for purchase
    # @return [Boolean] True if available for purchase
    def available_for_purchase?
      @data.key?('available_for_purchase') && @data['available_for_purchase'].nil?
    end

    # Check if role is a guild connections role
    # @return [Boolean] True if guild connections
    def guild_connections?
      @data.key?('guild_connections') && @data['guild_connections'].nil?
    end

    # Check if role is managed
    # @return [Boolean] True if managed
    def managed?
      bot? || integration?
    end
  end

  # Represents message flags
  #
  class MessageFlags
    # Flag bits
    FLAGS = {
      crossposted: 1 << 0,
      is_crosspost: 1 << 1,
      suppress_embeds: 1 << 2,
      source_message_deleted: 1 << 3,
      urgent: 1 << 4,
      has_thread: 1 << 5,
      ephemeral: 1 << 6,
      loading: 1 << 7,
      failed_to_mention_some_roles_in_thread: 1 << 8,
      suppress_notifications: 1 << 12,
      is_voice_message: 1 << 13
    }.freeze

    # @return [Integer] Flag value
    attr_reader :value

    # Initialize flags
    # @param value [Integer] Flag value
    def initialize(value = 0)
      @value = value.to_i
    end

    # Check if a flag is set
    # @param flag [Symbol] Flag name
    # @return [Boolean] True if set
    def has?(flag)
      bit = FLAGS[flag.to_sym]
      return false unless bit

      (@value & bit) == bit
    end

    FLAGS.each do |flag_name, _|
      define_method("#{flag_name}?") { has?(flag_name) }
    end
  end

  # Represents member flags
  #
  class MemberFlags
    # Flag bits
    FLAGS = {
      did_rejoin: 1 << 0,
      completed_onboarding: 1 << 1,
      bypasses_verification: 1 << 2,
      started_onboarding: 1 << 3,
      started_home_actions: 1 << 5,
      completed_home_actions: 1 << 6,
      automod_quarantined_bio: 1 << 7,
      automod_quarantined_username_or_nickname: 1 << 8
    }.freeze

    # @return [Integer] Flag value
    attr_reader :value

    # Initialize flags
    # @param value [Integer] Flag value
    def initialize(value = 0)
      @value = value.to_i
    end

    # Check if a flag is set
    # @param flag [Symbol] Flag name
    # @return [Boolean] True if set
    def has?(flag)
      bit = FLAGS[flag.to_sym]
      return false unless bit

      (@value & bit) == bit
    end

    FLAGS.each do |flag_name, _|
      define_method("#{flag_name}?") { has?(flag_name) }
    end
  end

  # Represents resolved data from interactions
  #
  class ResolvedData
    # @return [Hash] Raw data
    attr_reader :data

    # Initialize resolved data
    # @param data [Hash] Resolved data
    def initialize(data)
      @data = data || {}
    end

    # Get resolved users
    # @return [Hash<Snowflake, User>] Resolved users
    def users
      return {} unless @data['users']

      @data['users'].transform_values { |u| User.new(u) }
    end

    # Get resolved members
    # @return [Hash<Snowflake, Member>] Resolved members
    def members
      return {} unless @data['members']

      @data['members'].transform_values { |m| Member.new(m) }
    end

    # Get resolved roles
    # @return [Hash<Snowflake, Role>] Resolved roles
    def roles
      return {} unless @data['roles']

      @data['roles'].transform_values { |r| Role.new(r) }
    end

    # Get resolved channels
    # @return [Hash<Snowflake, Channel>] Resolved channels
    def channels
      return {} unless @data['channels']

      @data['channels'].transform_values { |c| Channel.new(c) }
    end

    # Get resolved messages
    # @return [Hash<Snowflake, Message>] Resolved messages
    def messages
      return {} unless @data['messages']

      @data['messages'].transform_values { |m| Message.new(m) }
    end

    # Get resolved attachments
    # @return [Hash<Snowflake, Attachment>] Resolved attachments
    def attachments
      return {} unless @data['attachments']

      @data['attachments'].transform_values { |a| Attachment.new(a) }
    end
  end

  # Represents a sticker
  #
  class Sticker < Entity
    # Sticker types
    TYPES = {
      standard: 1,
      guild: 2
    }.freeze

    # Sticker formats
    FORMATS = {
      png: 1,
      apng: 2,
      lottie: 3,
      gif: 4
    }.freeze

    attribute :name, type: :string
    attribute :tags, type: :string
    attribute :type, type: :integer
    attribute :format_type, type: :integer
    attribute :description, type: :string
    attribute :available, type: :boolean, default: true
    attribute :user, type: :hash
    attribute :sort_value, type: :integer
    attribute :pack_id, type: :snowflake

    # Check if standard sticker
    # @return [Boolean] True if standard
    def standard?
      type == 1
    end

    # Check if guild sticker
    # @return [Boolean] True if guild
    def guild?
      type == 2
    end

    # Get format type name
    # @return [Symbol] Format type
    def format
      FORMATS.key(format_type) || :unknown
    end

    # Check if animated
    # @return [Boolean] True if animated
    def animated?
      format_type == 2 || format_type == 4
    end

    # Get sticker URL
    # @return [String] Sticker URL
    def url
      format_ext = { 1 => 'png', 2 => 'png', 3 => 'json', 4 => 'gif' }[format_type] || 'png'

      if guild?
        "https://cdn.discordapp.com/stickers/#{id}.#{format_ext}"
      else
        "https://cdn.discordapp.com/stickers/#{id}.#{format_ext}"
      end
    end

    # Get guild ID
    # @return [Snowflake, nil] Guild ID
    def guild_id
      @raw_data['guild_id'] ? Snowflake.new(@raw_data['guild_id']) : nil
    end

    # Get creator
    # @return [User, nil] Creator
    def creator
      @user ||= User.new(@raw_data['user']) if @raw_data['user']
    end
  end
end
