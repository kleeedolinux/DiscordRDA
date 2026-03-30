# frozen_string_literal: true

module DiscordRDA
  # Discord Snowflake ID value object.
  # Provides extraction of timestamp, worker ID, process ID, and increment.
  #
  # Discord snowflakes are 64-bit integers with the following structure:
  # - 41 bits: timestamp (milliseconds since Discord epoch)
  # - 5 bits: worker ID
  # - 5 bits: process ID
  # - 12 bits: increment
  #
  # @example Creating a snowflake
  #   snowflake = Snowflake.new("1234567890123456789")
  #   snowflake.timestamp # => 2021-01-01 00:00:00 UTC
  #   snowflake.time # => Same as timestamp
  #
  class Snowflake
    # Discord epoch (January 1, 2015)
    DISCORD_EPOCH = 1_420_070_400_000

    # Bit masks for snowflake components
    WORKER_ID_BITS = 0x3E0000
    PROCESS_ID_BITS = 0x1F000
    INCREMENT_BITS = 0xFFF

    # @return [Integer] The raw snowflake value
    attr_reader :value

    class << self
      # Generate a new snowflake (for testing only - Discord generates real snowflakes)
      # @param time [Time] The time for the snowflake
      # @return [Snowflake] Generated snowflake
      def generate(time = Time.now.utc)
        timestamp = ((time.to_f * 1000).to_i - DISCORD_EPOCH) << 22
        increment = rand(0..INCREMENT_BITS)
        new(timestamp | increment)
      end

      # Parse a snowflake from string or integer
      # @param value [String, Integer] The snowflake value
      # @return [Snowflake] Parsed snowflake
      def parse(value)
        new(value)
      end
    end

    # Create a new snowflake
    # @param value [String, Integer] The snowflake value
    def initialize(value)
      @value = value.to_i
      freeze
    end

    # Get the timestamp from the snowflake
    # @return [Time] The timestamp (UTC)
    def timestamp
      @timestamp ||= Time.at(((@value >> 22) + DISCORD_EPOCH) / 1000.0).utc
    end
    alias time timestamp

    # Get the worker ID from the snowflake
    # @return [Integer] The worker ID
    def worker_id
      (@value & WORKER_ID_BITS) >> 17
    end

    # Get the process ID from the snowflake
    # @return [Integer] The process ID
    def process_id
      (@value & PROCESS_ID_BITS) >> 12
    end

    # Get the increment from the snowflake
    # @return [Integer] The increment
    def increment
      @value & INCREMENT_BITS
    end

    # Compare snowflakes by timestamp
    # @param other [Snowflake] Other snowflake to compare
    # @return [Integer] Comparison result
    def <=>(other)
      timestamp <=> other.timestamp
    end

    include Comparable

    # Check equality with another snowflake or value
    # @param other [Object] Object to compare
    # @return [Boolean] True if equal
    def ==(other)
      other.is_a?(Snowflake) && @value == other.value
    end
    alias eql? ==

    # Get the hash code
    # @return [Integer] Hash code
    def hash
      @value.hash
    end

    # Convert to integer
    # @return [Integer] The raw value
    def to_i
      @value
    end

    # Convert to string
    # @return [String] String representation
    def to_s
      @value.to_s
    end

    # Inspect the snowflake
    # @return [String] Inspect string
    def inspect
      "#<Snowflake value=#{@value} time=#{timestamp.iso8601}>"
    end
  end
end
