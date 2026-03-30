# frozen_string_literal: true

module DiscordRDA
  # Immutable configuration for DiscordRDA.
  # Uses frozen hash to prevent mutation after initialization.
  #
  # @example Creating configuration
  #   config = Configuration.new(
  #     token: ENV['DISCORD_TOKEN'],
  #     shards: :auto,
  #     intents: [:guilds, :guild_messages]
  #   )
  #
  class Configuration
    # Default configuration values
    DEFAULTS = {
      api_version: 10,
      gateway_encoding: :json,
      gateway_compression: :zlib_stream,
      shards: [0, 1],
      cache: :memory,
      max_reconnect_delay: 60.0,
      initial_reconnect_delay: 1.0,
      enable_resume: true,
      heartbeat_interval_buffer: 0.9,
      rest_timeout: 30.0,
      rest_open_timeout: 10.0,
      rest_read_timeout: 30.0,
      compression_threshold: 1024,
      intents: [:guilds],
      log_level: :info,
      log_format: :structured
    }.freeze

    # Valid intents mapping
    INTENTS = {
      guilds: 1 << 0,
      guild_members: 1 << 1,
      guild_moderation: 1 << 2,
      guild_emojis_and_stickers: 1 << 3,
      guild_integrations: 1 << 4,
      guild_webhooks: 1 << 5,
      guild_invites: 1 << 6,
      guild_voice_states: 1 << 7,
      guild_presences: 1 << 8,
      guild_messages: 1 << 9,
      guild_message_reactions: 1 << 10,
      guild_message_typing: 1 << 11,
      direct_messages: 1 << 12,
      direct_message_reactions: 1 << 13,
      direct_message_typing: 1 << 14,
      message_content: 1 << 15,
      guild_scheduled_events: 1 << 16,
      auto_moderation_configuration: 1 << 20,
      auto_moderation_execution: 1 << 21,
      guild_message_polls: 1 << 24,
      direct_message_polls: 1 << 25
    }.freeze

    # @return [String] Bot token
    attr_reader :token

    # @return [Integer] Discord API version
    attr_reader :api_version

    # @return [Symbol] Gateway encoding (:json or :etf)
    attr_reader :gateway_encoding

    # @return [Symbol] Gateway compression (:zlib_stream or nil)
    attr_reader :gateway_compression

    # @return [Array<Integer>, Symbol] Shards configuration or :auto
    attr_reader :shards

    # @return [Symbol] Cache backend (:memory or :redis)
    attr_reader :cache

    # @return [Float] Maximum reconnect delay in seconds
    attr_reader :max_reconnect_delay

    # @return [Float] Initial reconnect delay in seconds
    attr_reader :initial_reconnect_delay

    # @return [Boolean] Enable session resumption
    attr_reader :enable_resume

    # @return [Float] Heartbeat interval multiplier (0.0-1.0)
    attr_reader :heartbeat_interval_buffer

    # @return [Float] REST request timeout
    attr_reader :rest_timeout

    # @return [Float] REST connection open timeout
    attr_reader :rest_open_timeout

    # @return [Float] REST read timeout
    attr_reader :rest_read_timeout

    # @return [Integer] Compression threshold in bytes
    attr_reader :compression_threshold

    # @return [Array<Symbol>] Enabled gateway intents
    attr_reader :intents

    # @return [Symbol] Log level (:debug, :info, :warn, :error)
    attr_reader :log_level

    # @return [Symbol] Log format (:simple, :structured)
    attr_reader :log_format

    # Create a new configuration
    # @param options [Hash] Configuration options
    def initialize(options = {})
      config = DEFAULTS.merge(options)

      # Validate required options
      raise ArgumentError, 'Token is required' unless config[:token]

      @token = config[:token].freeze
      @api_version = config[:api_version].to_i
      @gateway_encoding = config[:gateway_encoding].to_sym
      @gateway_compression = config[:gateway_compression]&.to_sym
      @shards = normalize_shards(config[:shards])
      @cache = config[:cache].to_sym
      @max_reconnect_delay = config[:max_reconnect_delay].to_f
      @initial_reconnect_delay = config[:initial_reconnect_delay].to_f
      @enable_resume = !!config[:enable_resume]
      @heartbeat_interval_buffer = config[:heartbeat_interval_buffer].to_f.clamp(0.0, 1.0)
      @rest_timeout = config[:rest_timeout].to_f
      @rest_open_timeout = config[:rest_open_timeout].to_f
      @rest_read_timeout = config[:rest_read_timeout].to_f
      @compression_threshold = config[:compression_threshold].to_i
      @intents = normalize_intents(config[:intents])
      @log_level = config[:log_level].to_sym
      @log_format = config[:log_format].to_sym

      freeze
    end

    # Calculate the intents bitmask for Gateway identify
    # @return [Integer] Intents bitmask
    def intents_bitmask
      @intents.sum { |intent| INTENTS.fetch(intent, 0) }
    end

    # Get a new configuration with modified options
    # @param overrides [Hash] Options to override
    # @return [Configuration] New configuration instance
    def with(**overrides)
      self.class.new(to_h.merge(overrides))
    end

    # Convert configuration to hash
    # @return [Hash] Configuration as hash
    def to_h
      {
        token: @token,
        api_version: @api_version,
        gateway_encoding: @gateway_encoding,
        gateway_compression: @gateway_compression,
        shards: @shards,
        cache: @cache,
        max_reconnect_delay: @max_reconnect_delay,
        initial_reconnect_delay: @initial_reconnect_delay,
        enable_resume: @enable_resume,
        heartbeat_interval_buffer: @heartbeat_interval_buffer,
        rest_timeout: @rest_timeout,
        rest_open_timeout: @rest_open_timeout,
        rest_read_timeout: @rest_read_timeout,
        compression_threshold: @compression_threshold,
        intents: @intents,
        log_level: @log_level,
        log_format: @log_format
      }
    end

    private

    def normalize_shards(shards)
      return [:auto] if shards == :auto
      return shards if shards.is_a?(Array) && shards.all? { |s| s.is_a?(Array) }
      return [[0, 1]] unless shards.is_a?(Array) && shards.length == 2

      [shards]
    end

    def normalize_intents(intents)
      return [:guilds] unless intents.is_a?(Array)

      valid_intents = INTENTS.keys
      intents.select { |i| valid_intents.include?(i) }
    end
  end
end
