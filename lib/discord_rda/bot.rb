# frozen_string_literal: true

module DiscordRDA
  # Main Bot class for DiscordRDA.
  # Entry point for building Discord bots.
  #
  # @example Basic bot
  #   bot = DiscordRDA::Bot.new(token: ENV['DISCORD_TOKEN'])
  #   bot.on(:message_create) { |e| puts e.content }
  #   bot.run
  #
  class Bot
    # @return [Configuration] Bot configuration
    attr_reader :config

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [EventBus] Event bus
    attr_reader :event_bus

    # @return [EntityCache] Entity cache
    attr_reader :cache

    # @return [ShardManager] Shard manager
    attr_reader :shard_manager

    # @return [RestClient] REST client
    attr_reader :rest

    # @return [ScalableRestClient] Scalable REST client (if enabled)
    attr_reader :scalable_rest

    # @return [ReshardManager] Reshard manager
    attr_reader :reshard_manager

    # @return [HotReloadManager] Hot reload manager
    attr_reader :hot_reload_manager

    # @return [PluginRegistry] Plugin registry
    attr_reader :plugins

    # @return [Boolean] Whether bot is running
    attr_reader :running

    # @return [Hash] Registered slash commands
    attr_reader :slash_commands

    # Initialize a new bot
    # @param token [String] Bot token
    # @param options [Hash] Configuration options
    def initialize(token:, **options)
      @config = Configuration.new(options.merge(token: token))
      @logger = Logger.new(level: @config.log_level, format: @config.log_format)
      @event_bus = EventBus.new(logger: @logger)
      @cache = build_cache
      @shard_manager = ShardManager.new(@config, @event_bus, @logger)
      @rest = RestClient.new(@config, @logger)

      # Configure entity API clients
      Message.api = @rest
      Interaction.api = @rest

      setup_event_handlers
      setup_interaction_handlers

      # Initialize scalable components
      @scalable_rest = nil
      @reshard_manager = ReshardManager.new(self, @shard_manager, @logger)
      @hot_reload_manager = HotReloadManager.new(self, @logger)
      @plugins = PluginRegistry.new(logger: @logger)
      @slash_commands = {}
      @running = false
      @commands = {}

      setup_event_handlers
    end

    # Register a slash command (global or guild-specific)
    # @param name [String] Command name
    # @param description [String] Command description
    # @param options [Hash] Command options
    # @option options [String] :guild_id Guild-specific command (nil for global)
    # @option options [Array<Hash>] :options Command options
    # @option options [Integer] :default_member_permissions Default required permissions
    # @option options [Boolean] :dm_permission Whether works in DMs
    # @yield [CommandBuilder] DSL block for building command
    # @return [ApplicationCommand] Registered command
    def slash(name, description, **options, &block)
      builder = CommandBuilder.new(name, description)
      builder.dm_allowed(options[:dm_permission]) if options.key?(:dm_permission)
      builder.default_permissions(options[:default_member_permissions]) if options[:default_member_permissions]
      builder.nsfw(options[:nsfw]) if options[:nsfw]

      block.call(builder) if block

      cmd = builder.build
      cmd.instance_variable_set(:@application_id, me.id.to_s) rescue nil
      cmd.instance_variable_set(:@guild_id, options[:guild_id].to_s) if options[:guild_id]

      key = options[:guild_id] ? "#{name}:#{options[:guild_id]}" : name
      @slash_commands[key] = cmd

      # Register with Discord if we have application ID
      if cmd.application_id
        if options[:guild_id]
          cmd.create_guild(self, options[:guild_id])
        else
          cmd.create_global(self)
        end
      end

      @logger.info('Registered slash command', name: name, guild: options[:guild_id] || 'global')
      cmd
    end

    # Register a context menu command (user or message)
    # @param type [Symbol] :user or :message
    # @param name [String] Command name
    # @param options [Hash] Command options
    # @yield [Interaction] Handler block
    # @return [ApplicationCommand] Registered command
    def context_menu(type:, name:, **options, &block)
      cmd_type = type == :user ? 2 : 3
      options[:type] = cmd_type
      options[:description] = '' # Context menus don't have descriptions

      slash(name, '', **options, &block)
    end

    # Bulk register global commands (replaces existing)
    # @param commands [Array<CommandBuilder>] Commands to register
    # @return [Array<ApplicationCommand>] Registered commands
    def bulk_register_commands(commands)
      return [] unless me

      app_id = me.id.to_s
      payload = commands.map(&:to_h)

      data = @rest.put("/applications/#{app_id}/commands", body: payload)
      data.map { |cmd| ApplicationCommand.new(cmd) }
    end

    # Delete a global command
    # @param command_id [String] Command ID
    # @return [void]
    def delete_global_command(command_id)
      @rest.delete("/applications/#{me.id}/commands/#{command_id}") if me
    end

    # Delete a guild command
    # @param guild_id [String] Guild ID
    # @param command_id [String] Command ID
    # @return [void]
    def delete_guild_command(guild_id, command_id)
      @rest.delete("/applications/#{me.id}/guilds/#{guild_id}/commands/#{command_id}") if me
    end

    # Register an event handler
    # @param event [String, Symbol] Event type
    # @yield Event handler block
    # @return [Subscription] Subscription object
    def on(event, &block)
      @event_bus.on(event, &block)
    end

    # Register a one-time event handler
    # @param event [String, Symbol] Event type
    # @yield Event handler block
    # @return [Subscription] Subscription object
    def once(event, &block)
      @event_bus.once(event, &block)
    end

    # Wait for an event
    # @param event [String, Symbol] Event type
    # @param timeout [Float] Timeout in seconds
    # @yield Block to match event
    # @return [Event, nil] Event or nil if timeout
    def wait_for(event, timeout: nil, &block)
      @event_bus.wait_for(event, timeout: timeout, &block)
    end

    # Register a command
    # @param name [String] Command name
    # @param description [String] Command description
    # @param options [Array<Hash>] Command options
    # @yield Command handler
    # @return [void]
    def register_command(name, description = '', options = [], &block)
      @commands[name.to_s] = {
        description: description,
        options: options,
        handler: block
      }
    end
    alias command register_command

    # Register a plugin
    # @param plugin [Plugin] Plugin to register
    # @return [Boolean] True if registered
    def register_plugin(plugin)
      @plugins.register(plugin, self)
    end
    alias plugin register_plugin

    # Use middleware
    # @param middleware [Middleware] Middleware to use
    # @return [void]
    def use(middleware)
      @event_bus.use(middleware)
    end

    # Run the bot
    # @param async [Boolean] Run asynchronously
    # @return [void]
    def run(async: false)
      @running = true

      @logger.info('Starting DiscordRDA bot', version: VERSION, shards: @config.shards.length)

      # Start REST client
      @rest.start

      # Calculate shard count if auto
      shard_count = if @config.shards == [:auto]
                       @shard_manager.calculate_shard_count(:auto, @rest)
                     else
                       @config.shards.length
                     end

      @shard_manager.instance_variable_set(:@shard_count, shard_count)

      # Start shards
      if async
        Async { start_shards }
      else
        start_shards
      end
    end

    # Stop the bot
    # @return [void]
    def stop
      @logger.info('Stopping bot')
      @running = false
      @shard_manager.stop
      @rest.stop
    end

    # Update bot presence
    # @param status [String] online, idle, dnd, invisible
    # @param activity [Hash] Activity data
    # @return [void]
    def update_presence(status: 'online', activity: nil)
      @shard_manager.shards.each do |shard|
        shard.update_presence(status: status, activity: activity)
      end
    end

    # Get bot status
    # @return [Hash] Status information
    def status
      {
        running: @running,
        shards: @shard_manager.status,
        cache: @cache.stats,
        plugins: @plugins.stats
      }
    end

    # Fetch current user
    # @return [User] Bot user
    def me
      data = @rest.get('/users/@me')
      User.new(data)
    end

    # Get a guild by ID
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Guild, nil] Guild or nil
    def guild(guild_id)
      cached = @cache.guild(guild_id)
      return cached if cached

      data = @rest.get("/guilds/#{guild_id}")
      guild = Guild.new(data)
      @cache.cache_guild(guild)
      guild
    rescue RestClient::NotFoundError
      nil
    end

    # Get a channel by ID
    # @param channel_id [String, Snowflake] Channel ID
    # @return [Channel, nil] Channel or nil
    def channel(channel_id)
      cached = @cache.channel(channel_id)
      return cached if cached

      data = @rest.get("/channels/#{channel_id}")
      channel = Channel.new(data)
      @cache.cache_channel(channel)
      channel
    rescue RestClient::NotFoundError
      nil
    end

    # Send a message to a channel
    # @param channel_id [String, Snowflake] Channel ID
    # @param content [String] Message content
    # @param options [Hash] Message options
    # @return [Message] Sent message
    def send_message(channel_id, content = nil, **options)
      payload = { content: content }.merge(options).compact
      data = @rest.post("/channels/#{channel_id}/messages", body: payload)
      Message.new(data)
    end

    # Enable scalable REST client (queue-based rate limiting)
    # @param proxy [Hash] Optional proxy configuration
    # @return [void]
    def enable_scalable_rest(proxy: nil)
      @logger.info('Enabling scalable REST client')
      @scalable_rest = ScalableRestClient.new(@config, @logger, proxy: proxy)
      @scalable_rest.start
    end

    # Enable hot reload for development
    # @param watch_dir [String] Directory to watch
    # @return [void]
    def enable_hot_reload(watch_dir: 'lib')
      @logger.info('Enabling hot reload', watch_dir: watch_dir)
      @hot_reload_manager = HotReloadManager.new(self, @logger, watch_dir: watch_dir)
      @hot_reload_manager.enable
    end

    # Trigger zero-downtime resharding
    # @param new_shard_count [Integer] New shard count
    # @return [void]
    def reshard_to(new_shard_count)
      @logger.info('Triggering resharding', new_count: new_shard_count)
      @reshard_manager.reshard_to(new_shard_count)
    end

    # Enable auto-resharding based on guild count
    # @param max_guilds_per_shard [Integer] Max guilds per shard
    # @return [void]
    def enable_auto_reshard(max_guilds_per_shard: 1000)
      @event_bus.on(:guild_create) do |_event|
        guild_count = @shard_manager.total_guilds || 0
        @reshard_manager.auto_reshard_if_needed(guild_count, max_guilds_per_shard: max_guilds_per_shard)
      end
    end

    # Get invalid request bucket status
    # @return [Hash, nil] Invalid bucket status
    def invalid_bucket_status
      @scalable_rest&.invalid_bucket&.status
    end

    # Get analytics data (if analytics plugin registered)
    # @return [Hash] Analytics data
    def analytics
      analytics_plugin = @plugins.get(:Analytics)
      analytics_plugin&.summary || {}
    end

    def setup_interaction_handlers
      # Handle slash commands
      @event_bus.on(:interaction_create) do |event|
        interaction = event.interaction

        if interaction.command?
          handle_slash_command(interaction)
        elsif interaction.component?
          handle_component(interaction)
        elsif interaction.autocomplete?
          handle_autocomplete(interaction)
        elsif interaction.modal_submit?
          handle_modal_submit(interaction)
        end
      end
    end

    def handle_slash_command(interaction)
      cmd_name = interaction.command_name
      guild_id = interaction.guild_id

      # Try guild-specific command first, then global
      key = guild_id ? "#{cmd_name}:#{guild_id}" : cmd_name
      cmd = @slash_commands[key] || @slash_commands[cmd_name]

      if cmd && cmd.handler
        @logger.debug('Executing slash command', name: cmd_name, user: interaction.user&.id)
        begin
          cmd.handler.call(interaction)
        rescue => e
          @logger.error('Slash command error', command: cmd_name, error: e)
          # Send error response
          interaction.respond(content: "An error occurred while executing this command.", ephemeral: true) rescue nil
        end
      else
        @logger.warn('Unknown slash command', name: cmd_name)
        interaction.respond(content: "Unknown command: #{cmd_name}", ephemeral: true) rescue nil
      end
    end

    def handle_component(interaction)
      # Component interactions are handled by custom_id patterns or specific handlers
      custom_id = interaction.custom_id
      @logger.debug('Component interaction', custom_id: custom_id, user: interaction.user&.id)

      # Emit specific event for this component type
      event_type = case interaction.component_type
      when 2 then :button_click
      when 3 then :string_select
      when 5 then :user_select
      when 6 then :role_select
      when 7 then :mentionable_select
      when 8 then :channel_select
      else :component_interaction
      end

      @event_bus.emit(event_type, interaction)
    end

    def handle_autocomplete(interaction)
      # Autocomplete needs to be handled by the command that registered it
      cmd_name = interaction.command_name
      focused = interaction.focused_option

      @logger.debug('Autocomplete', command: cmd_name, option: focused&.dig('name'))

      # Emit autocomplete event
      @event_bus.emit(:autocomplete, interaction)
    end

    def handle_modal_submit(interaction)
      modal_id = interaction.custom_id
      values = interaction.modal_values

      @logger.debug('Modal submit', modal_id: modal_id, values: values.keys)

      # Emit modal submit event
      @event_bus.emit(:modal_submit, interaction)
    end

    private

    def build_cache
      store = case @config.cache
              when :redis
                RedisStore.new
              else
                MemoryStore.new
              end

      EntityCache.new(store, logger: @logger)
    end

    def setup_event_handlers
      # Cache entities on relevant events
      @event_bus.on(:guild_create) do |event|
        @cache.cache_guild(event.guild) if event.available?
      end

      @event_bus.on(:guild_update) do |event|
        @cache.cache_guild(event.guild)
      end

      @event_bus.on(:channel_create) do |event|
        @cache.cache_channel(event.channel)
      end

      @event_bus.on(:channel_update) do |event|
        @cache.cache_channel(event.channel)
      end

      @event_bus.on(:message_create) do |event|
        @cache.cache_message(event.message)
      end

      # Track ready state
      @event_bus.on(:ready) do |event|
        @logger.info('Bot ready', user: event.user&.username, guilds: event.guilds.length)
        @plugins.all.each { |p| p.ready(self) if p.enabled? }
      end
    end

    def start_shards
      if @config.shards == [:auto]
        @shard_manager.start
      else
        shard_ids = @config.shards.map(&:first)
        @shard_manager.start(shard_ids)
      end

      # Keep running
      sleep(1) while @running
    rescue Interrupt
      @logger.info('Interrupted')
      stop
    end
  end
end
