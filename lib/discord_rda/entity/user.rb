# frozen_string_literal: true

module DiscordRDA
  # Represents a Discord user.
  # Users are account-wide and not guild-specific.
  #
  class User < Entity
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
  end
end
