# frozen_string_literal: true

module DiscordRDA
  # Factory for creating Discord entities from API data.
  # Supports registration of custom entity types.
  #
  # @example Basic usage
  #   user = EntityFactory.create(:user, api_data)
  #   guild = EntityFactory.create(:guild, api_data)
  #
  # @example Custom entity registration
  #   class CustomGuild < Guild
  #     # custom implementation
  #   end
  #   EntityFactory.register(:guild, CustomGuild)
  #
  class EntityFactory
    # Default entity mappings
    DEFAULT_ENTITIES = {
      user: 'DiscordRDA::User',
      guild: 'DiscordRDA::Guild',
      channel: 'DiscordRDA::Channel',
      message: 'DiscordRDA::Message',
      role: 'DiscordRDA::Role',
      member: 'DiscordRDA::Member',
      emoji: 'DiscordRDA::Emoji',
      attachment: 'DiscordRDA::Attachment',
      embed: 'DiscordRDA::Embed',
      webhook: 'DiscordRDA::Webhook'
    }.freeze

    class << self
      # Register an entity type
      # @param type [Symbol] Entity type identifier
      # @param klass [Class] Entity class
      # @return [void]
      def register(type, klass)
        registry[type.to_sym] = klass
      end

      # Create an entity from data
      # @param type [Symbol] Entity type
      # @param data [Hash] API data
      # @return [Entity] Created entity
      def create(type, data)
        klass = registry[type.to_sym]
        raise ArgumentError, "Unknown entity type: #{type}" unless klass

        klass.new(data)
      end

      # Create multiple entities from array data
      # @param type [Symbol] Entity type
      # @param data_array [Array<Hash>] Array of API data
      # @return [Array<Entity>] Created entities
      def create_many(type, data_array)
        return [] unless data_array.is_a?(Array)

        data_array.map { |data| create(type, data) }
      end

      # Check if an entity type is registered
      # @param type [Symbol] Entity type
      # @return [Boolean] True if registered
      def registered?(type)
        registry.key?(type.to_sym)
      end

      # Get all registered types
      # @return [Array<Symbol>] Registered type names
      def registered_types
        registry.keys
      end

      # Unregister an entity type
      # @param type [Symbol] Entity type to unregister
      # @return [void]
      def unregister(type)
        registry.delete(type.to_sym)
      end

      # Reset to default registrations
      # @return [void]
      def reset!
        @registry = nil
      end

      private

      def registry
        @registry ||= build_default_registry
      end

      def build_default_registry
        DEFAULT_ENTITIES.transform_values { |class_name| Object.const_get(class_name) }
      end
    end
  end
end
