# frozen_string_literal: true

module DiscordRDA
  # Base class for all Discord entities.
  # Entities are immutable data objects representing Discord API resources.
  #
  # @abstract Subclass and implement attributes
  #
  class Entity
    # @return [Snowflake] The entity's unique ID
    attr_reader :id

    class << self
      # Define an attribute with type coercion
      # @param name [Symbol] Attribute name
      # @param type [Class, Proc] Type or coercion function
      # @param default [Object] Default value
      def attribute(name, type: nil, default: nil)
        define_method(name) do
          value = instance_variable_get("@#{name}")
          return default if value.nil?
          return value if type.nil?

          coerce_value(value, type)
        end
      end

      # Create an entity from API data
      # @param data [Hash] Raw API data
      # @return [Entity] New entity instance
      def from_hash(data)
        new(data)
      end

      private

      def coerce_value(value, type)
        case type
        when Proc then type.call(value)
        when :snowflake then Snowflake.new(value)
        when :time then Time.parse(value)
        when :integer then value.to_i
        when :string then value.to_s
        when :boolean then !!value
        else
          value.is_a?(type) ? value : type.new(value)
        end
      end
    end

    # Initialize entity with data
    # @param data [Hash] Entity data
    def initialize(data = {})
      normalized_data = data.each_with_object({}) do |(key, value), hash|
        hash[key.to_s] = value
      end

      normalized_data.each do |key, value|
        instance_variable_set("@#{key}", value)
      end

      @id = normalized_data['id'] ? Snowflake.new(normalized_data['id']) : nil
      @raw_data = normalized_data.freeze
      freeze
    end

    # Get raw API data
    # @return [Hash] The original data hash
    def to_h
      @raw_data
    end

    # Convert to JSON string
    # @return [String] JSON representation
    def to_json(*args)
      @raw_data.to_json(*args)
    end

    # Get creation time from snowflake ID
    # @return [Time, nil] Creation time or nil if no ID
    def created_at
      @id&.timestamp
    end

    # Check equality with another entity
    # @param other [Object] Object to compare
    # @return [Boolean] True if IDs match
    def ==(other)
      other.is_a?(self.class) && @id == other.id
    end
    alias eql? ==

    # Get hash code based on ID
    # @return [Integer] Hash code
    def hash
      @id.hash
    end

    # Inspect the entity
    # @return [String] Inspect string
    def inspect
      "#<#{self.class.name} id=#{@id}>"
    end

    private

    def coerce_value(value, type)
      self.class.send(:coerce_value, value, type)
    end
  end
end
