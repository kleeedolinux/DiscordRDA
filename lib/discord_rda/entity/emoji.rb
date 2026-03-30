# frozen_string_literal: true

module DiscordRDA
  # Represents a Discord emoji (custom or Unicode).
  #
  class Emoji < Entity
    attribute :name, type: :string
    attribute :roles, type: :array, default: []
    attribute :user, type: :hash
    attribute :require_colons, type: :boolean, default: true
    attribute :managed, type: :boolean, default: false
    attribute :animated, type: :boolean, default: false
    attribute :available, type: :boolean, default: true

    # Get the guild ID
    # @return [Snowflake, nil] Guild ID
    def guild_id
      @raw_data['guild_id'] ? Snowflake.new(@raw_data['guild_id']) : nil
    end

    # Check if emoji is animated
    # @return [Boolean] True if animated
    def animated?
      animated
    end

    # Check if emoji requires colons
    # @return [Boolean] True if requires colons
    def require_colons?
      require_colons
    end

    # Check if emoji is managed by integration
    # @return [Boolean] True if managed
    def managed?
      managed
    end

    # Check if emoji is available (not blocked by role restrictions)
    # @return [Boolean] True if available
    def available?
      available
    end

    # Get the emoji creator
    # @return [User, nil] Creator
    def user
      @user ||= User.new(@raw_data['user']) if @raw_data['user']
    end

    # Get role restrictions
    # @return [Array<Snowflake>] Role IDs
    def role_ids
      (@raw_data['roles'] || []).map { |r| Snowflake.new(r) }
    end

    # Get the emoji URL
    # @return [String] Emoji URL
    def url
      ext = animated? ? 'gif' : 'png'
      "https://cdn.discordapp.com/emojis/#{id}.#{ext}"
    end

    # Get the emoji mention string
    # @return [String] Emoji mention
    def mention
      prefix = animated? ? 'a' : ''
      "<#{prefix}:#{name}:#{id}>"
    end

    # Check if this is a Unicode emoji (no ID)
    # @return [Boolean] True if Unicode emoji
    def unicode?
      id.nil?
    end

    # Check if this is a custom emoji
    # @return [Boolean] True if custom emoji
    def custom?
      !id.nil?
    end

    # Get creation time (custom emojis only)
    # @return [Time, nil] Creation time
    def created_at
      id&.timestamp
    end
  end
end
