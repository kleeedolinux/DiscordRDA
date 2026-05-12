# frozen_string_literal: true

require 'async/websocket'
require 'async/http/internet'
require 'async/http/endpoint'
require 'io/stream'
require 'zlib'

module DiscordRDA
  # WebSocket client for Discord Gateway.
  # Handles connection, heartbeat, resume, and message dispatch.
  #
  # @example Basic usage
  #   gateway = GatewayClient.new(config, event_bus)
  #   gateway.connect
  #   gateway.run
  #
  class GatewayClient
    # Gateway versions
    DEFAULT_VERSION = 10

    # Gateway encoding
    ENCODING = 'json'

    # Gateway opcodes
    OPCODES = {
      dispatch: 0,
      heartbeat: 1,
      identify: 2,
      presence_update: 3,
      voice_state_update: 4,
      resume: 6,
      reconnect: 7,
      request_guild_members: 8,
      invalid_session: 9,
      hello: 10,
      heartbeat_ack: 11
    }.freeze

    # @return [Configuration] Configuration instance
    attr_reader :config

    # @return [EventBus] Event bus for dispatching events
    attr_reader :event_bus

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [Integer] Current sequence number
    attr_reader :sequence

    # @return [String] Session ID for resuming
    attr_reader :session_id

    # @return [String, nil] Resume gateway URL
    attr_reader :resume_gateway_url

    # @return [Boolean] Whether connected
    attr_reader :connected

    # Initialize the gateway client
    # @param config [Configuration] Bot configuration
    # @param event_bus [EventBus] Event bus instance
    # @param logger [Logger] Logger instance
    # @param shard_id [Integer] Shard ID
    # @param shard_count [Integer] Total shard count
    def initialize(config, event_bus, logger, shard_id: 0, shard_count: 1)
      @config = config
      @event_bus = event_bus
      @logger = logger
      @shard_id = shard_id
      @shard_count = shard_count
      @sequence = 0
      @session_id = nil
      @connected = false
      @heartbeat_interval = nil
      @heartbeat_task = nil
      @websocket = nil
      @zlib = nil
      @buffer = +''
      @last_heartbeat_ack = Time.now
      @resume_gateway_url = nil
    end

    # Connect to the Discord Gateway
    # @return [Async::Task] Connection task
    def connect
      Async do
        gateway_url = @resume_gateway_url || fetch_gateway_url
        endpoint = build_endpoint(gateway_url)

        @logger&.info('Connecting to Gateway', shard: @shard_id, url: gateway_url)

        @zlib = Zlib::Inflate.new(15 + 32) if @config.gateway_compression == :zlib_stream
        @buffer = +''

        begin
          Async::WebSocket::Client.connect(endpoint) do |websocket|
            @websocket = websocket
            @connected = true
            @logger&.info('Gateway connected', shard: @shard_id)

            handle_messages
          end
        rescue => e
          @logger&.error('Gateway connection error', error: e, shard: @shard_id)
          @connected = false
          raise
        end
      end
    end

    # Run the gateway event loop
    # @return [void]
    def run
      connect.wait
    end

    # Disconnect from the Gateway
    # @return [void]
    def disconnect
      @connected = false
      @heartbeat_task&.stop
      @websocket&.close
      @zlib&.close
      @logger&.info('Gateway disconnected', shard: @shard_id)
    end

    # Send an identify payload
    # @return [void]
    def identify
      payload = {
        op: OPCODES[:identify],
        d: {
          token: @config.token,
          properties: {
            os: 'linux',
            browser: 'discord_rda',
            device: 'discord_rda'
          },
          compress: @config.gateway_compression == :zlib_stream,
          large_threshold: 250,
          shard: [@shard_id, @shard_count],
          intents: @config.intents_bitmask
        }
      }

      send_payload(payload)
      @logger&.info('Sent identify', shard: @shard_id)
    end

    # Send a resume payload
    # @return [void]
    def resume
      return unless @session_id && @sequence > 0

      payload = {
        op: OPCODES[:resume],
        d: {
          token: @config.token,
          session_id: @session_id,
          seq: @sequence
        }
      }

      send_payload(payload)
      @logger&.info('Sent resume', shard: @shard_id, session: @session_id, seq: @sequence)
    end

    # Update presence
    # @param status [String] online, idle, dnd, invisible
    # @param activity [Hash] Activity data
    # @param afk [Boolean] Whether AFK
    # @return [void]
    def update_presence(status: 'online', activity: nil, afk: false)
      payload = {
        op: OPCODES[:presence_update],
        d: {
          since: afk ? Time.now.to_i * 1000 : nil,
          activities: activity ? [activity] : [],
          status: status,
          afk: afk
        }
      }

      send_payload(payload)
    end

    # Request guild members (chunking)
    # @param guild_id [String] Guild ID
    # @param query [String] Query string
    # @param limit [Integer] Member limit
    # @param presences [Boolean] Include presences
    # @param user_ids [Array<String>] Specific user IDs
    # @param nonce [String] Nonce for response
    # @return [void]
    def request_guild_members(guild_id, query: '', limit: 0, presences: false, user_ids: nil, nonce: nil)
      payload = {
        op: OPCODES[:request_guild_members],
        d: {
          guild_id: guild_id,
          query: query,
          limit: limit,
          presences: presences,
          user_ids: user_ids,
          nonce: nonce
        }.compact
      }

      send_payload(payload)
    end

    def restore_session_state(session_id:, sequence:, resume_gateway_url: nil)
      @session_id = session_id
      @sequence = sequence.to_i
      @resume_gateway_url = resume_gateway_url if resume_gateway_url
      @logger&.info('Restored gateway session state', shard: @shard_id, session: @session_id, seq: @sequence)
    end

    private

    def fetch_gateway_url
      # In production, fetch from /gateway/bot endpoint
      # For now, use hardcoded URL
      "wss://gateway.discord.gg/?v=#{DEFAULT_VERSION}&encoding=#{ENCODING}"
    end

    def build_endpoint(url)
      Async::HTTP::Endpoint.parse(url)
    end

    def handle_messages
      while @connected && (message = @websocket.read)
        process_message(message)
      end
    rescue Async::WebSocket::ConnectionClosed
      @logger&.warn('Gateway connection closed', shard: @shard_id)
      handle_disconnect
    end

    def process_message(message)
      data = decompress_if_needed(message)
      return unless data

      payload = Oj.load(data)
      handle_payload(payload)
    rescue Oj::ParseError => e
      @logger&.error('Failed to parse Gateway message', error: e, shard: @shard_id)
    end

    def decompress_if_needed(message)
      if @config.gateway_compression == :zlib_stream && @zlib
        chunk = message.to_str
        @buffer << chunk

        # Check for zlib suffix
        if chunk.byteslice(-4, 4) == "\x00\x00\xff\xff"
          decompressed = @zlib.inflate(@buffer)
          @buffer = +''
          decompressed
        else
          nil
        end
      else
        message.to_str
      end
    end

    def handle_payload(payload)
      op = payload['op']
      data = payload['d']
      seq = payload['s']
      event_type = payload['t']

      # Update sequence number
      @sequence = seq if seq

      case op
      when OPCODES[:dispatch]
        handle_dispatch(event_type, data)
      when OPCODES[:hello]
        handle_hello(data)
      when OPCODES[:heartbeat_ack]
        handle_heartbeat_ack
      when OPCODES[:reconnect]
        handle_reconnect
      when OPCODES[:invalid_session]
        handle_invalid_session(data)
      else
        @logger&.debug('Unhandled Gateway opcode', op: op, shard: @shard_id)
      end
    end

    def handle_dispatch(event_type, data)
      return unless event_type

      # Store session ID for resume
      if event_type == 'READY'
        @session_id = data['session_id']
        @resume_gateway_url = data['resume_gateway_url']
        @logger&.info('Received READY', shard: @shard_id, session: @session_id)
      elsif event_type == 'RESUMED'
        @logger&.info('Session resumed', shard: @shard_id)
      end

      # Create and dispatch event
      event = EventFactory.create(event_type, data, @shard_id)
      @event_bus&.publish(event_type, event)
    end

    def handle_hello(data)
      @heartbeat_interval = data['heartbeat_interval']
      @logger&.info('Received hello', interval: @heartbeat_interval, shard: @shard_id)

      # Start heartbeat task
      start_heartbeat

      # Identify or resume
      if @config.enable_resume && @session_id && @sequence > 0
        resume
      else
        identify
      end
    end

    def handle_heartbeat_ack
      @last_heartbeat_ack = Time.now
      @logger&.debug('Heartbeat acknowledged', shard: @shard_id)
    end

    def handle_reconnect
      @logger&.info('Received reconnect request', shard: @shard_id)
      disconnect
      sleep(@config.initial_reconnect_delay)
      connect
    end

    def handle_invalid_session(resumable)
      @logger&.warn('Invalid session', resumable: resumable, shard: @shard_id)

      if resumable
        sleep(1..5).to_a.sample
        resume
      else
        @session_id = nil
        @sequence = 0
        sleep(1..5).to_a.sample
        identify
      end
    end

    def handle_disconnect
      @connected = false
      @heartbeat_task&.stop

      # Attempt to resume if enabled
      if @config.enable_resume && @session_id
        @logger&.info('Attempting to resume', shard: @shard_id)
        sleep(@config.initial_reconnect_delay)
        connect
      end
    end

    def start_heartbeat
      @heartbeat_task = Async do
        loop do
          sleep(@heartbeat_interval * @config.heartbeat_interval_buffer / 1000.0)
          send_heartbeat
        end
      end
    end

    def send_heartbeat
      if Time.now - @last_heartbeat_ack > (@heartbeat_interval * 2 / 1000.0)
        @logger&.warn('Heartbeat timeout, reconnecting', shard: @shard_id)
        handle_disconnect
        return
      end

      payload = { op: OPCODES[:heartbeat], d: @sequence }
      send_payload(payload)
      @logger&.debug('Sent heartbeat', seq: @sequence, shard: @shard_id)
    end

    def send_payload(payload)
      return unless @websocket && @connected

      json = Oj.dump(payload, mode: :compat)
      @websocket.send(json)
      @websocket.flush
    end
  end
end
