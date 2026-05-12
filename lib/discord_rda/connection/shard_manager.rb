# frozen_string_literal: true

module DiscordRDA
  # Manages sharding for large Discord bots.
  # Automatically calculates shard count and distributes guilds.
  #
  class ShardManager
    # Maximum guilds per shard (Discord recommends 250, hard limit 2500)
    GUILDS_PER_SHARD = 1000

    # @return [Configuration] Configuration instance
    attr_reader :config

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [Integer] Total number of shards
    attr_reader :shard_count

    # @return [Array<GatewayClient>] Active gateway clients
    attr_reader :shards

    # @return [Integer] Total guilds across all shards
    attr_reader :total_guilds

    # @return [Boolean] Whether all shards are ready
    attr_reader :ready

    # Initialize shard manager
    # @param config [Configuration] Bot configuration
    # @param event_bus [EventBus] Event bus instance
    # @param logger [Logger] Logger instance
    def initialize(config, event_bus, logger, gateway_state: {})
      @config = config
      @event_bus = event_bus
      @logger = logger
      @gateway_state = gateway_state || {}
      @shard_count = nil
      @shards = []
      @total_guilds = nil
      @ready = false
      @mutex = Mutex.new
    end

    # Calculate or retrieve shard count
    # @param requested_shards [Array, Symbol] Requested shards or :auto
    # @param rest_client [RestClient] REST client for fetching session info
    # @return [Integer] Number of shards to use
    def calculate_shard_count(requested_shards, rest_client)
      if requested_shards == :auto
        # Fetch recommended shard count from Discord
        fetch_recommended_shards(rest_client)
      elsif requested_shards.is_a?(Array) && requested_shards.length == 1 && requested_shards[0] == :auto
        fetch_recommended_shards(rest_client)
      elsif requested_shards.is_a?(Array) && requested_shards.first.is_a?(Array)
        # Explicit shard ranges provided
        requested_shards.length
      else
        # Single shard or explicit count
        requested_shards.is_a?(Array) ? requested_shards[1] : 1
      end
    end

    # Get shard ID for a guild
    # @param guild_id [String, Integer] Guild ID
    # @param total_shards [Integer] Total shard count
    # @return [Integer] Shard ID
    def self.shard_for_guild(guild_id, total_shards)
      ((guild_id.to_i >> 22) % total_shards)
    end

    # Start all shards
    # @param shard_ids [Array<Integer>] Specific shard IDs to start (nil for all)
    # @return [void]
    def start(shard_ids = nil)
      shard_count = @shard_count || 1
      ids = shard_ids || (0...shard_count).to_a

      @logger&.info('Starting shards', count: ids.length, total: shard_count)

      ids.each do |shard_id|
        start_shard(shard_id, shard_count)
      end

      wait_for_ready
    end

    # Stop all shards
    # @return [void]
    def stop
      @logger&.info('Stopping all shards')
      @shards.each(&:disconnect)
      @shards.clear
      @ready = false
    end

    # Get shard by ID
    # @param shard_id [Integer] Shard ID
    # @return [GatewayClient, nil] Gateway client
    def shard(shard_id)
      @shards.find { |s| s.instance_variable_get(:@shard_id) == shard_id }
    end

    # Get status of all shards
    # @return [Hash] Status information
    def status
      {
        total_shards: @shard_count,
        active_shards: @shards.length,
        ready: @ready,
        guilds: @total_guilds,
        shard_statuses: @shards.map do |s|
          {
            id: s.instance_variable_get(:@shard_id),
            connected: s.connected,
            session: s.session_id
          }
        end
      }
    end

    # Check if shard is ready
    # @param shard_id [Integer] Shard ID
    # @return [Boolean] True if ready
    def shard_ready?(shard_id)
      shard(shard_id)&.connected
    end

    # Update total guild count
    # @param count [Integer] Total guilds
    # @return [void]
    def update_guild_count(count)
      @total_guilds = count
    end

    # Reconnect a specific shard
    # @param shard_id [Integer] Shard ID
    # @return [void]
    def reconnect_shard(shard_id)
      shard = shard(shard_id)
      return unless shard

      @logger&.info('Reconnecting shard', shard: shard_id)
      shard.disconnect
      sleep(@config.initial_reconnect_delay)
      shard.connect
    end

    # Spawn additional shards (hot scaling)
    # @param new_shard_count [Integer] New total shard count
    # @return [void]
    def respawn(new_shard_count)
      return if new_shard_count <= @shard_count.to_i

      @logger&.info('Respawning with more shards', old: @shard_count, new: new_shard_count)

      # Start new shards
      ((@shard_count || 0)...new_shard_count).each do |shard_id|
        start_shard(shard_id, new_shard_count)
      end

      @shard_count = new_shard_count
    end

    # Get session information from Discord
    # @param rest_client [RestClient] REST client
    # @return [Hash] Session info with url, shards, session_start_limit
    def fetch_session_info(rest_client)
      rest_client.get('/gateway/bot')
    end

    private

    def fetch_recommended_shards(rest_client)
      info = fetch_session_info(rest_client)
      recommended = info['shards'] || 1
      @logger&.info('Fetched recommended shard count', count: recommended)
      recommended
    rescue => e
      @logger&.error('Failed to fetch shard count, using 1', error: e)
      1
    end

    def start_shard(shard_id, shard_count)
      @logger&.info('Starting shard', id: shard_id, total: shard_count)

      gateway = GatewayClient.new(
        @config,
        @event_bus,
        @logger&.with_context(shard: shard_id),
        shard_id: shard_id,
        shard_count: shard_count
      )

      if (state = @gateway_state[shard_id] || @gateway_state[shard_id.to_s])
        gateway.restore_session_state(
          session_id: state['session_id'] || state[:session_id],
          sequence: state['sequence'] || state[:sequence],
          resume_gateway_url: state['resume_gateway_url'] || state[:resume_gateway_url]
        )
      end

      @mutex.synchronize { @shards << gateway }

      # Start gateway in background
      Async { gateway.run }
    rescue => e
      @logger&.error('Failed to start shard', shard: shard_id, error: e)
    end

    def wait_for_ready
      return if @shards.empty?

      @logger&.info('Waiting for shards to be ready')

      loop do
        ready_count = @shards.count(&:connected)
        total = @shards.length

        @logger&.info('Shard status', ready: ready_count, total: total)

        if ready_count == total
          @ready = true
          @logger&.info('All shards ready')
          break
        end

        sleep(1)
      end
    end
  end
end
