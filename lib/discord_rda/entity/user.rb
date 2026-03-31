# frozen_string_literal: true

require 'base64'
require_relative 'channel'

module DiscordRDA
  # Represents a Discord user.
  # Users are account-wide and not guild-specific.
  #
  class User < Entity
    # Class-level API client
    class << self
      attr_accessor :api
    end

    attribute :username, type: :string
    attribute :discriminator, type: :string
    attribute :global_name, type: :string
    attribute :avatar, type: :string
    attribute :bot, type: :boolean, default: false
    attribute :system, type: :boolean, default: false
    attribute :mfa_enabled, type: :boolean, default: false
    attribute :locale, type: :string
    attribute :verified, type: :boolean, default: false
    attribute :email, type: :string
    attribute :flags, type: :integer, default: 0
    attribute :premium_type, type: :integer, default: 0
    attribute :public_flags, type: :integer, default: 0
    attribute :avatar_decoration, type: :string
    attribute :display_name, type: :string

    # Get the user's effective name (global_name or username)
    # @return [String] The display name
    def display_name
      global_name || username
    end

    # Check if user is a bot account
    # @return [Boolean] True if bot
    def bot?
      @raw_data['bot'] || false
    end

    # Check if this is the system user
    # @return [Boolean] True if system user
    def system?
      @raw_data['system'] || false
    end

    # Get the user's avatar URL
    # @param format [String] Image format (png, jpg, webp, gif)
    # @param size [Integer] Image size (power of 2, 16-4096)
    # @return [String] Avatar URL
    def avatar_url(format: nil, size: nil)
      return default_avatar_url unless avatar

      ext = format || (animated_avatar? ? 'gif' : 'png')
      url = "https://cdn.discordapp.com/avatars/#{id}/#{avatar}.#{ext}"
      url += "?size=#{size}" if size
      url
    end

    # Get the default avatar URL based on discriminator
    # @return [String] Default avatar URL
    def default_avatar_url
      discrim = discriminator.to_i
      index = discrim % 5
      "https://cdn.discordapp.com/embed/avatars/#{index}.png"
    end

    # Check if the avatar is animated (GIF)
    # @return [Boolean] True if animated
    def animated_avatar?
      avatar&.start_with?('a_')
    end

    # Get mention string for the user
    # @return [String] Mention string
    def mention
      "<@#{id}>"
    end

    # Get the user's banner URL
    # @param format [String] Image format
    # @param size [Integer] Image size
    # @return [String, nil] Banner URL or nil if no banner
    def banner_url(format: 'png', size: nil)
      return nil unless @raw_data['banner']

      url = "https://cdn.discordapp.com/banners/#{id}/#{@raw_data['banner']}.#{format}"
      url += "?size=#{size}" if size
      url
    end

    # Check if user has a specific public flag
    # @param flag [Symbol] Flag name
    # @return [Boolean] True if flag is set
    def public_flag?(flag)
      flags = {
        staff: 1 << 0,
        partner: 1 << 1,
        hypesquad: 1 << 2,
        bug_hunter_level_1: 1 << 3,
        hypesquad_bravery: 1 << 6,
        hypesquad_brilliance: 1 << 7,
        hypesquad_balance: 1 << 8,
        early_supporter: 1 << 9,
        team_user: 1 << 10,
        bug_hunter_level_2: 1 << 14,
        verified_bot: 1 << 16,
        verified_developer: 1 << 17,
        certified_moderator: 1 << 18,
        bot_http_interactions: 1 << 19,
        active_developer: 1 << 22
      }

      flag_value = flags[flag.to_sym]
      return false unless flag_value

      (public_flags & flag_value) == flag_value
    end

    # Create a DM channel with this user
    # @return [Channel, nil] DM channel
    def create_dm_channel
      return nil unless self.class.api

      data = self.class.api.post('/users/@me/channels', body: { recipient_id: id.to_s })
      Channel.new(data)
    end

    # Get guilds the current user is in
    # @param limit [Integer] Max number of guilds (1-200, default 200)
    # @param after [String] Get guilds after this guild ID
    # @param before [String] Get guilds before this guild ID
    # @param with_counts [Boolean] Include approximate member and presence counts
    # @return [Array<Hash>] Guild objects (partial, not full Guild entities)
    def self.get_current_user_guilds(limit: 200, after: nil, before: nil, with_counts: false)
      return [] unless api

      params = { limit: limit, with_counts: with_counts }
      params[:after] = after if after
      params[:before] = before if before

      api.get('/users/@me/guilds', params: params)
    end

    # Leave a guild
    # @param guild_id [String, Snowflake] Guild ID to leave
    # @return [void]
    def self.leave_guild(guild_id)
      return unless api

      api.delete("/users/@me/guilds/#{guild_id}")
    end

    # Get current user's guild member information
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Hash, nil] Guild member object
    def self.get_current_user_guild_member(guild_id)
      return nil unless api

      api.get("/users/@me/guilds/#{guild_id}/member")
    rescue RestClient::NotFoundError
      nil
    end

    # Modify the current user
    # @param username [String] New username
    # @param avatar [File, String] New avatar (file or base64 data URI)
    # @return [User] Updated user
    def self.modify_current_user(username: nil, avatar: nil)
      return nil unless api

      body = {}
      body[:username] = username if username

      if avatar
        body[:avatar] = if avatar.respond_to?(:read)
                          # Convert file to base64 data URI
                          data = avatar.read
                          base64 = Base64.strict_encode64(data)
                          ext = File.extname(avatar.respond_to?(:path) ? avatar.path : 'png').delete('.')
                          "data:image/#{ext};base64,#{base64}"
                        else
                          avatar
                        end
      end

      data = api.patch('/users/@me', body: body)
      User.new(data)
    end

    # Get user connections (for current user only)
    # @return [Array<Hash>] Connected accounts
    def self.get_connections
      return [] unless api

      api.get('/users/@me/connections')
    end

    # Get user's application role connection
    # @param application_id [String, Snowflake] Application ID
    # @return [Hash, nil] Role connection metadata
    def self.get_application_role_connection(application_id)
      return nil unless api

      api.get("/users/@me/applications/#{application_id}/role-connection")
    rescue RestClient::NotFoundError
      nil
    end

    # Update user's application role connection
    # @param application_id [String, Snowflake] Application ID
    # @param platform_name [String] Platform name
    # @param platform_username [String] Platform username
    # @param metadata [Hash] Role connection metadata
    # @return [Hash] Updated role connection
    def self.update_application_role_connection(application_id, platform_name: nil, platform_username: nil, metadata: {})
      return nil unless api

      body = {
        platform_name: platform_name,
        platform_username: platform_username,
        metadata: metadata
      }.compact

      api.put("/users/@me/applications/#{application_id}/role-connection", body: body)
    end
  end
end
