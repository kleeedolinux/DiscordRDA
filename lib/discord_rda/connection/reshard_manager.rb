# frozen_string_literal: true

module DiscordRDA
  # Zero-downtime resharding manager.
  # Allows adding/removing shards without stopping the bot.
  #
  class ReshardManager
    # @return [Bot] Bot instance
    attr_reader :bot

    # @return [ShardManager] Original shard manager
    attr_reader :shard_manager

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [Boolean] Whether resharding is in progress
    attr_reader :resharding

    # @return [Array<GatewayClient>] New shards being added
    attr_reader :new_shards

    # @return [Array<GatewayClient>] Old shards being removed
    attr_reader :old_shards

    # Initialize reshard manager
    # @param bot [Bot] Bot instance
    # @param shard_manager [ShardManager] Shard manager
    # @param logger [Logger] Logger instance
    def initialize(bot, shard_manager, logger)
      @bot = bot
      @shard_manager = shard_manager
      @logger = logger
      @resharding = false
      @new_shards = []
      @old_shards = []
      @mutex = Mutex.new
    end

    # Start zero-downtime resharding to new shard count
    # @param new_shard_count [Integer] New total shard count
    # @return [void]
    def reshard_to(new_shard_count)
      return if new_shard_count <= @shard_manager.shard_count.to_i
      return if @resharding

      @mutex.synchronize do
        @resharding = true
        old_count = @shard_manager.shard_count || 1

        @logger.info('Starting zero-downtime resharding',
          old_count: old_count,
          new_count: new_shard_count
        )

        # Step 1: Identify which shards need to be moved
        guilds_per_shard = calculate_guilds_per_shard(new_shard_count)

        # Step 2: Start new shards
        start_new_shards(old_count, new_shard_count)

        # Step 3: Wait for new shards to be ready
        wait_for_new_shards_ready

        # Step 4: Begin session transfer
        transfer_sessions

        # Step 5: Mark old shards for shutdown
        mark_old_shards_for_shutdown

        # Step 6: Wait for old shards to drain
        wait_for_old_shards_drain

        # Step 7: Update shard manager state
        finalize_reshard

        @logger.info('Resharding complete', new_shard_count: new_shard_count)
        @resharding = false
      end
    rescue => e
      @logger.error('Resharding failed', error: e)
      @resharding = false
      raise
    end

    # Calculate optimal guilds per shard
    # @param shard_count [Integer] Target shard count
    # @return [Integer] Guilds per shard
    def calculate_guilds_per_shard(shard_count)
      total_guilds = @shard_manager.total_guilds || 1000
      (total_guilds / shard_count.to_f).ceil
    end

    # Get reshard status
    # @return [Hash] Status information
    def status
      @mutex.synchronize do
        {
          resharding: @resharding,
          new_shards: @new_shards.length,
          old_shards: @old_shards.length,
          total_shards: @shard_manager.shard_count
        }
      end
    end

    private

    def start_new_shards(old_count, new_count)
      @logger.info('Starting new shards', range: "#{old_count}..#{new_count - 1}")

      (old_count...new_count).each do |shard_id|
        gateway = GatewayClient.new(
          @bot.config,
          @bot.event_bus,
          @logger&.with_context(shard: shard_id, type: :new),
          shard_id: shard_id,
          shard_count: new_count
        )

        @new_shards << gateway

        # Start in background
        Async { gateway.run }
      end
    end

    def wait_for_new_shards_ready
      @logger.info('Waiting for new shards to be ready')

      loop do
        ready_count = @new_shards.count(&:connected)
        total = @new_shards.length

        @logger.info('New shard status', ready: ready_count, total: total)

        break if ready_count == total

        sleep(1)
      end
    end

    def transfer_sessions
      @logger.info('Transferring sessions to new shards')

      old_count = @shard_manager.shard_count
      new_count = @new_shards.first&.instance_variable_get(:@shard_count)

      return unless old_count && new_count && new_count > old_count

      # Get all guilds currently managed by old shards
      guilds_to_transfer = []

      @shard_manager.shards.each do |shard|
        # Extract guild IDs from shard's guild cache or session data
        shard_guilds = shard.instance_variable_get(:@guilds) || []
        shard_guilds.each do |guild_id|
          old_shard_id = (guild_id.to_i >> 22) % old_count
          new_shard_id = (guild_id.to_i >> 22) % new_count

          # This guild needs to move to a new shard
          if old_shard_id != new_shard_id
            guilds_to_transfer << {
              guild_id: guild_id,
              old_shard_id: old_shard_id,
              new_shard_id: new_shard_id,
              new_shard: @new_shards.find { |s| shard_id(s) == new_shard_id }
            }
          end
        end
      end

      @logger.info('Guilds need transfer', count: guilds_to_transfer.length)

      # Request guild member chunks on new shards for transferred guilds
      guilds_by_new_shard = guilds_to_transfer.group_by { |g| g[:new_shard_id] }

      guilds_by_new_shard.each do |shard_id, guilds|
        new_shard = @new_shards.find { |s| shard_id(s) == shard_id }
        next unless new_shard

        guild_ids = guilds.map { |g| g[:guild_id].to_s }
        @logger.debug('Requesting guild members on new shard', shard: shard_id, guilds: guild_ids.length)

        # Request GUILD_MEMBERS_CHUNK for each guild
        guild_ids.each do |guild_id|
          new_shard.request_guild_members(guild_id)
        end
      end

      @logger.info('Session transfer complete', transferred_guilds: guilds_to_transfer.length)
    end

    def mark_old_shards_for_shutdown
      @logger.info('Marking old shards for graceful shutdown')

      @shard_manager.shards.each do |shard|
        @old_shards << shard
        shard.instance_variable_set(:@should_shutdown, true)
      end
    end

    def wait_for_old_shards_drain
      @logger.info('Waiting for old shards to drain')

      timeout = 60 # seconds
      start_time = Time.now

      loop do
        # Check if all old shards have no pending work
        all_drained = @old_shards.all? { |s| shard_drained?(s) }

        if all_drained
          @logger.info('All old shards drained')
          break
        end

        if Time.now - start_time > timeout
          @logger.warn('Timeout waiting for old shards, forcing shutdown')
          break
        end

        sleep(1)
      end

      # Disconnect old shards
      @old_shards.each(&:disconnect)
    end

    def shard_drained?(shard)
      return true unless shard

      # Check multiple indicators that shard has no pending work:

      # 1. Check if shard has marked itself for shutdown
      should_shutdown = shard.instance_variable_get(:@should_shutdown)
      return false unless should_shutdown

      # 2. Check pending REST requests (via ScalableRestClient queues)
      rest_pending = 0
      if @bot.scalable_rest
        identifier = "Bot #{@bot.config.token}"
        # Count requests in queues associated with this shard
        @bot.scalable_rest.queues.each do |key, queue|
          if key.start_with?(identifier)
            rest_pending += queue.pending.length
          end
        end
      end

      # 3. Check event queue depth
      event_queue = shard.instance_variable_get(:@event_queue) || []
      event_count = event_queue.is_a?(Array) ? event_queue.length : 0

      # 4. Check heartbeat status (last ack within 2 seconds)
      last_heartbeat_ack = shard.instance_variable_get(:@last_heartbeat_ack)
      heartbeat_ok = if last_heartbeat_ack
        (Time.now.to_f - last_heartbeat_ack.to_f) < 2.0
      else
        true # No heartbeat tracking means assume OK
      end

      # 5. Check gateway connection state
      connected = shard.respond_to?(:connected) ? shard.connected : false

      # Shard is drained when:
      # - Marked for shutdown AND
      # - No pending REST requests AND
      # - Event queue is empty AND
      # - Heartbeat is recent OR not connected
      drained = should_shutdown &&
                rest_pending == 0 &&
                event_count == 0 &&
                (heartbeat_ok || !connected)

      @logger.debug('Shard drain check',
        shard: shard_id(shard),
        should_shutdown: should_shutdown,
        rest_pending: rest_pending,
        event_count: event_count,
        heartbeat_ok: heartbeat_ok,
        connected: connected,
        drained: drained
      ) if drained

      drained
    end

    def finalize_reshard
      @logger.info('Finalizing reshard')

      @mutex.synchronize do
        # Update shard manager
        @shard_manager.instance_variable_set(:@shards, @new_shards)
        @shard_manager.instance_variable_set(:@shard_count, @new_shards.first&.instance_variable_get(:@shard_count))

        # Clear old references
        @new_shards = []
        @old_shards = []

        # Mark as ready
        @shard_manager.instance_variable_set(:@ready, true)
      end
    end

    # Auto-reshard based on guild count
    # @param guild_count [Integer] Current guild count
    # @param max_guilds_per_shard [Integer] Maximum guilds per shard
    # @return [Boolean] True if resharding was triggered
    def auto_reshard_if_needed(guild_count, max_guilds_per_shard: 1000)
      current_shards = @shard_manager.shard_count || 1
      recommended_shards = (guild_count / max_guilds_per_shard.to_f).ceil

      if recommended_shards > current_shards
        @logger.info('Auto-reshard triggered',
          current: current_shards,
          recommended: recommended_shards,
          guilds: guild_count
        )

        reshard_to(recommended_shards)
        true
      else
        false
      end
    end
  end
end
