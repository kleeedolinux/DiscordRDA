# frozen_string_literal: true

module DiscordRDA
  # Represents a Discord guild member.
  # Combines User data with guild-specific information.
  #
  class Member < Entity
    # Member inherits ID from user
    def id
      user&.id
    end

    # @return [User] The underlying user
    attr_reader :user

    # @return [String] Nickname in the guild
    attr_reader :nick

    # @return [String] Guild avatar hash
    attr_reader :avatar

    # @return [Array<Snowflake>] Role IDs
    attr_reader :roles

    # @return [Time] When member joined
    attr_reader :joined_at

    # @return [Time] When member started boosting
    attr_reader :premium_since

    # @return [Boolean] Whether member is deafened
    attr_reader :deaf

    # @return [Boolean] Whether member is muted
    attr_reader :mute

    # @return [Integer] Guild flags
    attr_reader :flags

    # @return [Boolean] Whether member is pending
    attr_reader :pending

    # @return [String] Permissions for this member in channel
    attr_reader :permissions

    # @return [Time] When member's timeout expires
    attr_reader :communication_disabled_until

    # Create a new member
    # @param data [Hash] Member data
    def initialize(data = {})
      super

      @user = data['user'] ? User.new(data['user']) : nil
      @nick = data['nick']
      @avatar = data['avatar']
      @roles = (data['roles'] || []).map { |r| Snowflake.new(r) }
      @joined_at = data['joined_at'] ? Time.parse(data['joined_at']) : nil
      @premium_since = data['premium_since'] ? Time.parse(data['premium_since']) : nil
      @deaf = data['deaf'] || false
      @mute = data['mute'] || false
      @flags = data['flags'] || 0
      @pending = data['pending'] || false
      @permissions = data['permissions']
      @communication_disabled_until = data['communication_disabled_until'] ? Time.parse(data['communication_disabled_until']) : nil
    end

    # Get the user object
    # @return [User] User object
    def user
      @user
    end

    # Get member's effective name (nickname or username)
    # @return [String] Display name
    def display_name
      nick || user&.display_name || user&.username
    end

    # Get mention string
    # @return [String] Member mention
    def mention
      "<@!#{id}>"
    end

    # Check if member has a nickname
    # @return [Boolean] True if has nickname
    def nick?
      !nick.nil?
    end

    # Get member's guild avatar URL
    # @param format [String] Image format
    # @param size [Integer] Image size
    # @return [String] Avatar URL
    def avatar_url(format: 'png', size: nil)
      if avatar
        url = "https://cdn.discordapp.com/guilds/#{guild_id}/users/#{id}/avatars/#{avatar}.#{format}"
        url += "?size=#{size}" if size
        url
      else
        user&.avatar_url(format: format, size: size)
      end
    end

    # Check if member is server deafened
    # @return [Boolean] True if deafened
    def deaf?
      deaf
    end

    # Check if member is server muted
    # @return [Boolean] True if muted
    def mute?
      mute
    end

    # Check if member has pending membership screening
    # @return [Boolean] True if pending
    def pending?
      pending
    end

    # Check if member is currently timed out
    # @return [Boolean] True if timed out
    def timed_out?
      return false unless communication_disabled_until

      communication_disabled_until > Time.now.utc
    end

    # Check if member is boosting
    # @return [Boolean] True if boosting
    def boosting?
      !premium_since.nil?
    end

    # Get boost start time
    # @return [Time, nil] When boosting started
    def boost_since
      premium_since
    end

    # Get how long member has been in the guild
    # @return [Float] Duration in seconds
    def duration_in_guild
      return 0 unless joined_at

      Time.now.utc - joined_at
    end

    # Get how long member has been boosting
    # @return [Float, nil] Duration in seconds or nil if not boosting
    def boost_duration
      return nil unless premium_since

      Time.now.utc - premium_since
    end

    # Get guild ID
    # @return [Snowflake, nil] Guild ID
    def guild_id
      @raw_data['guild_id'] ? Snowflake.new(@raw_data['guild_id']) : nil
    end

    # Get permission set for this member
    # @return [Permission, nil] Permissions
    def permission_set
      return nil unless permissions

      Permission.new(permissions.to_i)
    end

    # Check if member has a specific role
    # @param role_id [String, Snowflake] Role ID to check
    # @return [Boolean] True if has role
    def has_role?(role_id)
      role_snowflake = role_id.is_a?(Snowflake) ? role_id : Snowflake.new(role_id)
      roles.include?(role_snowflake)
    end

    # Get the highest role position
    # @param guild_roles [Array<Role>] All guild roles
    # @return [Integer] Highest position
    def highest_role_position(guild_roles)
      member_roles = guild_roles.select { |r| has_role?(r.id) }
      member_roles.map(&:position).max || 0
    end

    # Check if member can perform action on target
    # Compares roles and permissions
    # @param target [Member] Target member
    # @param guild_roles [Array<Role>] Guild roles for comparison
    # @return [Boolean] True if this member outranks target
    def can_act_on?(target, guild_roles)
      return false if target.id == id # Can't act on self
      return false if target.id == guild_id # Can't act on owner

      highest_role_position(guild_roles) > target.highest_role_position(guild_roles)
    end

    # Get creation time (from user)
    # @return [Time, nil] Account creation time
    def created_at
      user&.created_at
    end

    # Delegate methods to user
    def method_missing(method, *args, &block)
      if user&.respond_to?(method)
        user.public_send(method, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      user&.respond_to?(method) || super
    end

    # Check if this member is the guild owner
    # @param guild_owner_id [Snowflake] Guild owner ID
    # @return [Boolean] True if owner
    def owner?(guild_owner_id)
      id == guild_owner_id
    end

    # Get member flags
    # @return [MemberFlags] Member flags
    def member_flags
      MemberFlags.new(flags)
    end

    # Check if member has completed onboarding
    # @return [Boolean] True if completed
    def completed_onboarding?
      !flags.nil? && (flags & 2) == 2
    end

    # Check if member has bypassed verification
    # @return [Boolean] True if bypassed
    def bypasses_verification?
      !flags.nil? && (flags & 4) == 4
    end

    # Check if member started onboarding
    # @return [Boolean] True if started
    def started_onboarding?
      !flags.nil? && (flags & 1) == 1
    end

    # Get member's display color from highest colored role
    # @param guild_roles [Array<Role>] All guild roles
    # @return [Color] Display color
    def display_color(guild_roles)
      member_roles = guild_roles.select { |r| has_role?(r.id) && r.color > 0 }
      return Color.new(0) if member_roles.empty?

      highest_colored = member_roles.max_by(&:position)
      Color.new(highest_colored.color)
    end
  end
end
