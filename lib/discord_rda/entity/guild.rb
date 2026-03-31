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

    # Get Role objects from raw data
    # @return [Array<Role>] Guild roles
    def role_objects
      (@raw_data['roles'] || []).map { |r| Role.new(r.merge('guild_id' => id.to_s)) }
    end

    # Get a role by ID
    # @param role_id [String, Snowflake] Role ID
    # @return [Role, nil] Role or nil
    def role(role_id)
      role_data = (@raw_data['roles'] || []).find { |r| r['id'] == role_id.to_s }
      Role.new(role_data.merge('guild_id' => id.to_s)) if role_data
    end

    # Get Emoji objects from raw data
    # @return [Array<Emoji>] Guild emojis
    def emoji_objects
      (@raw_data['emojis'] || []).map { |e| Emoji.new(e) }
    end

    # Get discovery splash URL
    # @param format [String] Image format
    # @param size [Integer] Image size
    # @return [String, nil] Discovery splash URL or nil
    def discovery_splash_url(format: 'png', size: nil)
      return nil unless @raw_data['discovery_splash']

      url = "https://cdn.discordapp.com/discovery-splashes/#{id}/#{@raw_data['discovery_splash']}.#{format}"
      url += "?size=#{size}" if size
      url
    end

    # Check if guild has banner feature
    # @return [Boolean] True if banner feature enabled
    def banner_feature?
      feature?(:banner)
    end

    # Check if guild has invite splash feature
    # @return [Boolean] True if invite splash enabled
    def invite_splash?
      feature?(:invite_splash)
    end

    # Check if guild has animated banner
    # @return [Boolean] True if animated banner feature enabled
    def animated_banner?
      feature?(:animated_banner)
    end

    # Check if guild has animated icon
    # @return [Boolean] True if animated icon feature enabled
    def animated_icon?
      feature?(:animated_icon)
    end

    # Get boost count as tier name
    # @return [String] Boost tier
    def boost_tier
      premium_tier_name
    end

    # Get number of boosts
    # @return [Integer] Boost count
    def boost_count
      premium_subscription_count
    end

    # Check if boost progress bar is enabled
    # @return [Boolean] True if enabled
    def boost_progress_bar?
      premium_progress_bar_enabled
    end

    # Get system channel flags as array
    # @return [Array<Symbol>] Enabled flags
    def system_channel_flags_list
      flags = []
      return flags unless system_channel_flags

      flags << :suppress_join_notifications if system_channel_flags & 1 == 1
      flags << :suppress_premium_subscriptions if system_channel_flags & 2 == 2
      flags << :suppress_guild_reminder_notifications if system_channel_flags & 4 == 4
      flags << :suppress_join_notification_replies if system_channel_flags & 8 == 8
      flags << :suppress_role_subscription_purchase_notifications if system_channel_flags & 16 == 16
      flags << :suppress_role_subscription_purchase_notification_replies if system_channel_flags & 32 == 32
      flags
    end

    # Get preferred locale as symbol
    # @return [Symbol] Locale
    def locale
      preferred_locale&.gsub('-', '_')&.downcase&.to_sym
    end

    # Check if guild is available (not unavailable due to outage)
    # @return [Boolean] True if available
    def available?
      !@raw_data['unavailable']
    end

    # Check if guild is unavailable
    # @return [Boolean] True if unavailable
    def unavailable?
      @raw_data['unavailable'] || false
    end

    # Class-level API client
    class << self
      attr_accessor :api
    end

    # Fetch a member from this guild
    # @param user_id [String, Snowflake] User ID
    # @return [Member, nil] Member or nil if not found
    def fetch_member(user_id)
      return nil unless self.class.api

      data = self.class.api.get("/guilds/#{id}/members/#{user_id}")
      Member.new(data.merge('guild_id' => id.to_s))
    rescue RestClient::NotFoundError
      nil
    end

    # Fetch members from this guild (simplified pagination)
    # @param limit [Integer] Max members (1-1000)
    # @param after [String, Snowflake] Get members after this user ID
    # @return [Array<Member>] Guild members
    def fetch_members(limit: 100, after: nil)
      return [] unless self.class.api

      params = { limit: limit }
      params[:after] = after.to_s if after

      data = self.class.api.get("/guilds/#{id}/members", params: params)
      data.map { |m| Member.new(m.merge('guild_id' => id.to_s)) }
    end

    # Fetch channels in this guild
    # @return [Array<Channel>] Guild channels
    def fetch_channels
      return [] unless self.class.api

      data = self.class.api.get("/guilds/#{id}/channels")
      data.map { |c| Channel.new(c) }
    end

    # Fetch roles in this guild
    # @return [Array<Role>] Guild roles
    def fetch_roles
      return [] unless self.class.api

      data = self.class.api.get("/guilds/#{id}/roles")
      data.map { |r| Role.new(r.merge('guild_id' => id.to_s)) }
    end

    # Fetch bans in this guild
    # @param limit [Integer] Max bans (1-1000)
    # @return [Array<Hash>] Bans with user and reason
    def fetch_bans(limit: 100)
      return [] unless self.class.api

      data = self.class.api.get("/guilds/#{id}/bans", params: { limit: limit })
      data.map { |b| { user: User.new(b['user']), reason: b['reason'] } }
    end

    # Fetch active invites for this guild
    # @return [Array<Hash>] Guild invites
    def fetch_invites
      return [] unless self.class.api

      self.class.api.get("/guilds/#{id}/invites")
    end

    # Fetch guild preview (for lurkable guilds)
    # @return [Hash, nil] Guild preview data
    def fetch_preview
      return nil unless self.class.api

      self.class.api.get("/guilds/#{id}/preview")
    rescue RestClient::NotFoundError
      nil
    end

    # Fetch welcome screen
    # @return [Hash, nil] Welcome screen data
    def fetch_welcome_screen
      return nil unless self.class.api

      self.class.api.get("/guilds/#{id}/welcome-screen")
    rescue RestClient::NotFoundError
      nil
    end

    # Fetch onboarding settings
    # @return [Hash, nil] Onboarding data
    def fetch_onboarding
      return nil unless self.class.api

      self.class.api.get("/guilds/#{id}/onboarding")
    rescue RestClient::NotFoundError
      nil
    end

    # Fetch voice regions for this guild
    # @return [Array<Hash>] Voice regions
    def fetch_voice_regions
      return [] unless self.class.api

      self.class.api.get("/guilds/#{id}/regions")
    end

    # Fetch webhooks for this guild
    # @return [Array<Hash>] Guild webhooks
    def fetch_webhooks
      return [] unless self.class.api

      self.class.api.get("/guilds/#{id}/webhooks")
    end

    # Fetch integrations for this guild
    # @return [Array<Hash>] Guild integrations
    def fetch_integrations
      return [] unless self.class.api

      self.class.api.get("/guilds/#{id}/integrations")
    end

    # Fetch stickers for this guild
    # @return [Array<Sticker>] Guild stickers
    def fetch_stickers
      return [] unless self.class.api

      data = self.class.api.get("/guilds/#{id}/stickers")
      data.map { |s| Sticker.new(s) }
    end

    # Fetch a specific guild sticker
    # @param sticker_id [String, Snowflake] Sticker ID
    # @return [Sticker, nil] Sticker or nil
    def fetch_sticker(sticker_id)
      return nil unless self.class.api

      data = self.class.api.get("/guilds/#{id}/stickers/#{sticker_id}")
      Sticker.new(data)
    rescue RestClient::NotFoundError
      nil
    end

    # Create a guild sticker
    # @param name [String] Sticker name (2-30 characters)
    # @param description [String] Sticker description (2-100 characters, optional for guild stickers)
    # @param tags [String] Sticker tags (comma-separated, 2-200 characters total)
    # @param file [File, String, IO] Sticker file (PNG, APNG, Lottie, or GIF, max 512KB, 320x320)
    # @param reason [String] Audit log reason
    # @return [Sticker] Created sticker
    def create_sticker(name:, description:, tags:, file:, reason: nil)
      return nil unless self.class.api

      headers = {}
      headers['X-Audit-Log-Reason'] = CGI.escape(reason) if reason

      # Determine content type based on file extension
      file_path = file.respond_to?(:path) ? file.path : file.to_s
      ext = File.extname(file_path).downcase

      content_type = case ext
                     when '.png' then 'image/png'
                     when '.apng' then 'image/apng'
                     when '.gif' then 'image/gif'
                     when '.json' then 'application/json'
                     else 'application/octet-stream'
                     end

      # Create a file wrapper with proper metadata
      file_wrapper = if file.respond_to?(:read)
                       file
                     else
                       File.open(file, 'rb')
                     end

      # Set content type if not already set
      unless file_wrapper.respond_to?(:content_type)
        def file_wrapper.content_type
          @content_type ||= 'application/octet-stream'
        end
        file_wrapper.instance_variable_set(:@content_type, content_type)
      end

      unless file_wrapper.respond_to?(:original_filename)
        def file_wrapper.original_filename
          @original_filename ||= 'sticker.png'
        end
        file_wrapper.instance_variable_set(:@original_filename, File.basename(file_path))
      end

      payload = {
        name: name,
        description: description,
        tags: tags
      }

      data = self.class.api.post(
        "/guilds/#{id}/stickers",
        body: payload,
        files: { 'file' => file_wrapper },
        headers: headers
      )

      Sticker.new(data)
    ensure
      file_wrapper.close if file_wrapper.respond_to?(:close) && !file_wrapper.closed? && file_wrapper != file
    end

    # Modify a guild sticker
    # @param sticker_id [String, Snowflake] Sticker ID
    # @param name [String] New name
    # @param description [String] New description
    # @param tags [String] New tags
    # @param reason [String] Audit log reason
    # @return [Sticker] Updated sticker
    def modify_sticker(sticker_id, name: nil, description: nil, tags: nil, reason: nil)
      return nil unless self.class.api

      headers = {}
      headers['X-Audit-Log-Reason'] = CGI.escape(reason) if reason

      body = { name: name, description: description, tags: tags }.compact

      data = self.class.api.patch("/guilds/#{id}/stickers/#{sticker_id}", body: body, headers: headers)
      Sticker.new(data)
    end

    # Delete a guild sticker
    # @param sticker_id [String, Snowflake] Sticker ID
    # @param reason [String] Audit log reason
    # @return [void]
    def delete_sticker(sticker_id, reason: nil)
      return unless self.class.api

      headers = {}
      headers['X-Audit-Log-Reason'] = CGI.escape(reason) if reason

      self.class.api.delete("/guilds/#{id}/stickers/#{sticker_id}", headers: headers)
    end

    # Fetch widget settings
    # @return [Hash, nil] Widget settings
    def fetch_widget_settings
      return nil unless self.class.api

      self.class.api.get("/guilds/#{id}/widget")
    rescue RestClient::NotFoundError
      nil
    end

    # Get widget URL
    # @return [String] Widget URL
    def widget_url
      "https://discord.com/widget?id=#{id}&theme=dark"
    end

    # Get guild vanity URL with code
    # @return [String, nil] Vanity URL
    def vanity_invite_url
      return nil unless vanity_url_code

      "https://discord.gg/#{vanity_url_code}"
    end

    # Check if guild has vanity URL feature
    # @return [Boolean] True if has vanity URL
    def has_vanity_url?
      !vanity_url_code.nil? && !vanity_url_code.empty?
    end

    # Check if guild has description
    # @return [Boolean] True if has description
    def has_description?
      description && !description.empty?
    end

    # Get role count
    # @return [Integer] Number of roles
    def role_count
      @raw_data['roles']&.length || 0
    end

    # Get emoji count
    # @return [Integer] Number of emojis
    def emoji_count
      @raw_data['emojis']&.length || 0
    end

    # Check if guild is likely community server
    # @return [Boolean] True if community guild
    def likely_community?
      community? || rules_channel_id || public_updates_channel_id
    end

    # Get moderation level description
    # @return [String] Moderation level
    def moderation_level
      verification_level_name
    end

    # Check if guild requires verification
    # @return [Boolean] True if requires verification
    def requires_verification?
      verification_level > 0
    end

    # Check if guild has 2FA requirement for moderation
    # @return [Boolean] True if requires 2FA
    def requires_2fa?
      mfa_level == 1
    end

    # Check if guild has explicit content filter enabled
    # @return [Boolean] True if has content filter
    def has_content_filter?
      explicit_content_filter > 0
    end

    # Check if guild has NSFW content allowed
    # @return [Boolean] True if NSFW allowed
    def nsfw_allowed?
      nsfw_level > 0
    end

    # Get human-readable guild summary
    # @return [Hash] Guild summary
    def summary
      {
        id: id.to_s,
        name: name,
        member_count: member_count,
        online_count: approximate_presence_count,
        boost_tier: boost_tier,
        boost_count: boost_count,
        features: features,
        large: large?,
        community: community?,
        partnered: partnered?,
        verified: verified?,
        available: available?
      }
    end
  end
end
