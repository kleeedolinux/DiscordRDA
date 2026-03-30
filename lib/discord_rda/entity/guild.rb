# frozen_string_literal: true

module DiscordRDA
  # Represents a Discord guild (server).
  #
  class Guild < Entity
    attribute :name, type: :string
    attribute :icon, type: :string
    attribute :description, type: :string
    attribute :splash, type: :string
    attribute :discovery_splash, type: :string
    attribute :owner_id, type: :snowflake
    attribute :region, type: :string
    attribute :afk_channel_id, type: :snowflake
    attribute :afk_timeout, type: :integer
    attribute :widget_enabled, type: :boolean, default: false
    attribute :widget_channel_id, type: :snowflake
    attribute :verification_level, type: :integer, default: 0
    attribute :default_message_notifications, type: :integer, default: 0
    attribute :explicit_content_filter, type: :integer, default: 0
    attribute :roles, type: :array, default: []
    attribute :emojis, type: :array, default: []
    attribute :features, type: :array, default: []
    attribute :mfa_level, type: :integer, default: 0
    attribute :system_channel_id, type: :snowflake
    attribute :system_channel_flags, type: :integer, default: 0
    attribute :rules_channel_id, type: :snowflake
    attribute :max_presences, type: :integer
    attribute :max_members, type: :integer
    attribute :vanity_url_code, type: :string
    attribute :premium_tier, type: :integer, default: 0
    attribute :premium_subscription_count, type: :integer, default: 0
    attribute :preferred_locale, type: :string, default: 'en-US'
    attribute :public_updates_channel_id, type: :snowflake
    attribute :max_video_channel_users, type: :integer
    attribute :approximate_member_count, type: :integer
    attribute :approximate_presence_count, type: :integer
    attribute :nsfw_level, type: :integer, default: 0
    attribute :premium_progress_bar_enabled, type: :boolean, default: false

    # Get the owner's snowflake ID
    # @return [Snowflake] Owner ID
    def owner_id
      @owner_id ||= @raw_data['owner_id'] ? Snowflake.new(@raw_data['owner_id']) : nil
    end

    # Get icon URL
    # @param format [String] Image format
    # @param size [Integer] Image size
    # @return [String, nil] Icon URL or nil if no icon
    def icon_url(format: 'png', size: nil)
      return nil unless @raw_data['icon']

      url = "https://cdn.discordapp.com/icons/#{id}/#{@raw_data['icon']}.#{format}"
      url += "?size=#{size}" if size
      url
    end

    # Get splash URL (invite background)
    # @param format [String] Image format
    # @param size [Integer] Image size
    # @return [String, nil] Splash URL or nil
    def splash_url(format: 'png', size: nil)
      return nil unless @raw_data['splash']

      url = "https://cdn.discordapp.com/splashes/#{id}/#{@raw_data['splash']}.#{format}"
      url += "?size=#{size}" if size
      url
    end

    # Check if guild has a specific feature
    # @param feature [String, Symbol] Feature name
    # @return [Boolean] True if feature is enabled
    def feature?(feature)
      features.include?(feature.to_s.upcase)
    end

    # Get available features
    # @return [Array<String>] Enabled features
    def features
      @raw_data['features'] || []
    end

    # Check if guild is large (250+ members)
    # @return [Boolean] True if large
    def large?
      (@raw_data['large'] || @raw_data['member_count'].to_i >= 250)
    end

    # Get member count
    # @return [Integer] Member count
    def member_count
      @raw_data['member_count'] || @raw_data['approximate_member_count'] || 0
    end

    # Get verification level name
    # @return [String] Verification level
    def verification_level_name
      %w[none low medium high very_high][verification_level] || 'unknown'
    end

    # Get default message notifications setting name
    # @return [String] Notification setting
    def default_message_notifications_name
      %w[all_messages only_mentions][default_message_notifications] || 'unknown'
    end

    # Get explicit content filter name
    # @return [String] Content filter setting
    def explicit_content_filter_name
      %w[disabled_members_without_roles all_members][explicit_content_filter] || 'unknown'
    end

    # Get MFA level name
    # @return [String] MFA level
    def mfa_level_name
      %w[none elevated][mfa_level] || 'unknown'
    end

    # Get premium tier name (boost level)
    # @return [String] Premium tier
    def premium_tier_name
      %w[none tier_1 tier_2 tier_3][premium_tier] || 'unknown'
    end

    # Get NSFW level name
    # @return [String] NSFW level
    def nsfw_level_name
      %w[default explicit safe age_restricted][nsfw_level] || 'unknown'
    end

    # Check if community guild
    # @return [Boolean] True if community feature enabled
    def community?
      feature?(:community)
    end

    # Check if partnered guild
    # @return [Boolean] True if partnered
    def partnered?
      feature?(:partnered)
    end

    # Check if verified guild
    # @return [Boolean] True if verified
    def verified?
      feature?(:verified)
    end

    # Get approximate member count
    # @return [Integer, nil] Approximate member count from preview
    def approximate_member_count
      @raw_data['approximate_member_count']
    end

    # Get approximate presence count
    # @return [Integer, nil] Approximate online members
    def approximate_presence_count
      @raw_data['approximate_presence_count']
    end

    # Get vanity invite URL
    # @return [String, nil] Vanity URL or nil
    def vanity_url
      return nil unless @raw_data['vanity_url_code']

      "https://discord.gg/#{@raw_data['vanity_url_code']}"
    end
  end
end
