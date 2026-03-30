# frozen_string_literal: true

module DiscordRDA
  # Represents a Discord role.
  # Roles are guild-specific permission sets.
  #
  class Role < Entity
    attribute :name, type: :string
    attribute :color, type: :integer, default: 0
    attribute :hoist, type: :boolean, default: false
    attribute :icon, type: :string
    attribute :unicode_emoji, type: :string
    attribute :position, type: :integer, default: 0
    attribute :permissions, type: :string
    attribute :managed, type: :boolean, default: false
    attribute :mentionable, type: :boolean, default: false
    attribute :tags, type: :hash
    attribute :flags, type: :integer, default: 0

    # Get the guild ID
    # @return [Snowflake, nil] Guild ID
    def guild_id
      @raw_data['guild_id'] ? Snowflake.new(@raw_data['guild_id']) : nil
    end

    # Get permissions as Permission object
    # @return [Permission] Role permissions
    def permission_set
      Permission.new(permissions.to_i)
    end

    # Check if role is managed by an integration
    # @return [Boolean] True if managed
    def managed?
      managed
    end

    # Check if role is mentionable
    # @return [Boolean] True if mentionable
    def mentionable?
      mentionable
    end

    # Check if role is hoisted (shown separately in member list)
    # @return [Boolean] True if hoisted
    def hoisted?
      hoist
    end

    # Check if this is the @everyone role
    # @return [Boolean] True if @everyone
    def everyone?
      name == '@everyone'
    end

    # Get mention string for the role
    # @return [String] Role mention
    def mention
      "<@&#{id}>"
    end

    # Get color as Color object
    # @return [Color] Role color
    def color_object
      Color.new(color)
    end

    # Get color as hex string
    # @return [String] Hex color
    def color_hex
      color_object.to_s
    end

    # Get RGB values
    # @return [Array<Integer>] RGB array
    def rgb
      color_object.rgb
    end

    # Get icon URL if role has custom icon
    # @param format [String] Image format
    # @param size [Integer] Image size
    # @return [String, nil] Icon URL or nil
    def icon_url(format: 'png', size: nil)
      return nil unless icon

      url = "https://cdn.discordapp.com/role-icons/#{guild_id}/#{id}/#{icon}.#{format}"
      url += "?size=#{size}" if size
      url
    end

    # Get role tags
    # @return [RoleTags] Role tags
    def role_tags
      RoleTags.new(tags || {})
    end

    # Check if role is integrated
    # @return [Boolean] True if bot or integration role
    def integrated?
      tags&.key?('bot_id') || tags&.key?('integration_id')
    end

    # Check if role is a premium subscriber role
    # @return [Boolean] True if premium subscriber role
    def premium_subscriber?
      tags&.key?('premium_subscriber')
    end

    # Check if role has a subscription listing
    # @return [Boolean] True if subscription listing
    def subscription_listing?
      tags&.key?('subscription_listing_id')
    end

    # Check if role is available for purchase
    # @return [Boolean] True if available for purchase
    def available_for_purchase?
      tags&.key?('available_for_purchase')
    end

    # Check if role is a guild's linked role
    # @return [Boolean] True if linked role
    def guild_connections?
      tags&.key?('guild_connections')
    end

    # Compare roles by position
    # @param other [Role] Other role
    # @return [Integer] Comparison result
    def <=>(other)
      other.position <=> position
    end

    include Comparable

    # Check if this role is higher than another
    # @param other [Role] Other role
    # @return [Boolean] True if higher position
    def higher_than?(other)
      position > other.position
    end

    # Check if this role is lower than another
    # @param other [Role] Other role
    # @return [Boolean] True if lower position
    def lower_than?(other)
      position < other.position
    end

    # Get creation time
    # @return [Time] Role creation time
    def created_at
      id.timestamp
    end
  end
end
