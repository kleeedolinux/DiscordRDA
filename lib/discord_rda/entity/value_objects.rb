# frozen_string_literal: true

module DiscordRDA
  # Represents Discord permissions as a bitfield.
  # Provides easy checking and manipulation of individual permissions.
  #
  # @example Checking permissions
  #   perms = Permission.new(0x8) # Administrator
  #   perms.administrator? # => true
  #
  # @example Building permissions
  #   perms = Permission.new
  #   perms.add(:send_messages)
  #   perms.add(:read_messages)
  #   perms.value # => 0x400 | 0x800
  #
  class Permission
    # All permission bits with their names
    BITS = {
      create_instant_invite: 1 << 0,
      kick_members: 1 << 1,
      ban_members: 1 << 2,
      administrator: 1 << 3,
      manage_channels: 1 << 4,
      manage_guild: 1 << 5,
      add_reactions: 1 << 6,
      view_audit_log: 1 << 7,
      priority_speaker: 1 << 8,
      stream: 1 << 9,
      view_channel: 1 << 10,
      send_messages: 1 << 11,
      send_tts_messages: 1 << 12,
      manage_messages: 1 << 13,
      embed_links: 1 << 14,
      attach_files: 1 << 15,
      read_message_history: 1 << 16,
      mention_everyone: 1 << 17,
      use_external_emojis: 1 << 18,
      view_guild_insights: 1 << 19,
      connect: 1 << 20,
      speak: 1 << 21,
      mute_members: 1 << 22,
      deafen_members: 1 << 23,
      move_members: 1 << 24,
      use_vad: 1 << 25,
      change_nickname: 1 << 26,
      manage_nicknames: 1 << 27,
      manage_roles: 1 << 28,
      manage_webhooks: 1 << 29,
      manage_emojis_and_stickers: 1 << 30,
      use_application_commands: 1 << 31,
      request_to_speak: 1 << 32,
      manage_events: 1 << 33,
      manage_threads: 1 << 34,
      create_public_threads: 1 << 35,
      create_private_threads: 1 << 36,
      use_external_stickers: 1 << 37,
      send_messages_in_threads: 1 << 38,
      use_embedded_activities: 1 << 39,
      moderate_members: 1 << 40,
      monetization_analytics: 1 << 41,
      use_soundboard: 1 << 42,
      create_expressions: 1 << 43,
      create_events: 1 << 44,
      use_external_sounds: 1 << 45,
      send_voice_messages: 1 << 46,
      send_polls: 1 << 49,
      use_external_apps: 1 << 50
    }.freeze

    # All permission names
    NAMES = BITS.keys.freeze

    # All permissions value
    ALL = BITS.values.reduce(:|)

    # None permissions value
    NONE = 0

    # @return [Integer] The permission bitfield value
    attr_reader :value

    class << self
      # Get all available permission names
      # @return [Array<Symbol>] Permission names
      def names
        NAMES
      end

      # Get the bit value for a permission
      # @param permission [Symbol] Permission name
      # @return [Integer] Bit value
      def bit(permission)
        BITS[permission.to_sym] || 0
      end

      # Create from an array of permission names
      # @param permissions [Array<Symbol>] Permission names
      # @return [Permission] New permission object
      def from_array(permissions)
        new(permissions.sum { |p| bit(p) })
      end
    end

    # Initialize with a permission value
    # @param value [Integer, String] Permission bitfield
    def initialize(value = 0)
      @value = value.to_i
    end

    # Check if a specific permission is granted
    # @param permission [Symbol] Permission to check
    # @return [Boolean] True if permission is granted
    def has?(permission)
      bit = BITS[permission.to_sym]
      return false unless bit

      administrator? || (@value & bit) == bit
    end
    alias include? has?

    # Add a permission
    # @param permission [Symbol] Permission to add
    # @return [Permission] Self for chaining
    def add(permission)
      bit = BITS[permission.to_sym]
      @value |= bit if bit
      self
    end

    # Remove a permission
    # @param permission [Symbol] Permission to remove
    # @return [Permission] Self for chaining
    def remove(permission)
      bit = BITS[permission.to_sym]
      @value &= ~bit if bit
      self
    end

    # Toggle a permission
    # @param permission [Symbol] Permission to toggle
    # @return [Permission] Self for chaining
    def toggle(permission)
      has?(permission) ? remove(permission) : add(permission)
    end

    # Get all granted permissions as array of symbols
    # @return [Array<Symbol>] Granted permissions
    def granted
      BITS.keys.select { |name| has?(name) }
    end

    # Check for administrator permission
    # @return [Boolean] True if administrator
    def administrator?
      (@value & BITS[:administrator]) == BITS[:administrator]
    end

    # Check for multiple permissions
    # @param permissions [Array<Symbol>] Permissions to check
    # @return [Boolean] True if all granted
    def has_all?(*permissions)
      permissions.all? { |p| has?(p) }
    end

    # Check for any of multiple permissions
    # @param permissions [Array<Symbol>] Permissions to check
    # @return [Boolean] True if any granted
    def has_any?(*permissions)
      permissions.any? { |p| has?(p) }
    end

    # Missing permissions from a list
    # @param permissions [Array<Symbol>] Required permissions
    # @return [Array<Symbol>] Missing permissions
    def missing(*permissions)
      permissions.reject { |p| has?(p) }
    end

    # Combine with another permission set (union)
    # @param other [Permission] Other permission
    # @return [Permission] Combined permissions
    def union(other)
      self.class.new(@value | other.value)
    end
    alias | union

    # Intersect with another permission set
    # @param other [Permission] Other permission
    # @return [Permission] Intersection
    def intersection(other)
      self.class.new(@value & other.value)
    end
    alias & intersection

    # Subtract another permission set
    # @param other [Permission] Permissions to remove
    # @return [Permission] Remaining permissions
    def difference(other)
      self.class.new(@value & ~other.value)
    end
    alias - difference

    # Check if this permission set includes all of another
    # @param other [Permission] Other permission
    # @return [Boolean] True if this includes all of other
    def superset?(other)
      (@value & other.value) == other.value
    end

    # Check if this permission set is a subset of another
    # @param other [Permission] Other permission
    # @return [Boolean] True if this is subset of other
    def subset?(other)
      other.superset?(self)
    end

    # Check if no permissions are set
    # @return [Boolean] True if empty
    def empty?
      @value == 0
    end

    # Convert to integer
    # @return [Integer] Bitfield value
    def to_i
      @value
    end

    # Convert to string representation
    # @return [String] String value
    def to_s
      @value.to_s
    end

    # Check equality
    # @param other [Object] Other object
    # @return [Boolean] True if equal
    def ==(other)
      other.is_a?(Permission) && @value == other.value
    end

    # Hash code
    # @return [Integer] Hash code
    def hash
      @value.hash
    end

    # Inspect
    # @return [String] Inspect string
    def inspect
      perms = granted.map(&:to_s).join(', ')
      "#<Permission #{perms}>"
    end

    # Dynamic permission checkers
    BITS.each_key do |permission|
      define_method("#{permission}?") do
        has?(permission)
      end
    end
  end
end
