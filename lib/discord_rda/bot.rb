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

    # @return [Tracer] Trace helper
    attr_reader :tracer

    # @return [ErrorTracker] Error tracking helper
    attr_reader :error_tracker

    # @return [RestartManager] Instant restart helper
    attr_reader :restart_manager

    # @return [ExecutionSupervisor] Fault-tolerant execution supervisor
    attr_reader :supervisor

    # @return [Hash] Boot-time restart state
    attr_reader :restart_state

    # @return [ActiveRecordSystem, nil] ActiveRecord integration helper
    attr_reader :active_record

    # @return [Boolean] Whether bot is running
    attr_reader :running

    # @return [Hash] Registered slash commands
    attr_reader :slash_commands

    # Initialize a new bot
    # @param token [String] Bot token
    # @param options [Hash] Configuration options
    def initialize(token:, **options)
      @config = Configuration.new(options.merge(token: token))
      @logger = Logger.new(
        level: @config.log_level,
        format: @config.log_format,
        file_path: @config.log_file_path,
        rotate_age: @config.log_rotate_age,
        rotate_size: @config.log_rotate_size
      )
      @restart_manager = RestartManager.new(logger: @logger)
      @restart_state = @restart_manager.consume_boot_state
      @tracer = Tracer.new(enabled: @config.trace_enabled, logger: @logger)
      @error_tracker = ErrorTracker.new(enabled: @config.error_tracking, logger: @logger)
      @supervisor = ExecutionSupervisor.new(logger: @logger)
      @event_bus = EventBus.new(logger: @logger)
      @cache = build_cache
      @shard_manager = ShardManager.new(@config, @event_bus, @logger, gateway_state: restart_gateway_state)
      @rest = RestClient.new(@config, @logger)

      # Configure entity API clients
      configure_entity_apis(@rest)

      setup_event_handlers
      setup_interaction_handlers

      # Initialize scalable components
      @scalable_rest = nil
      @reshard_manager = ReshardManager.new(self, @shard_manager, @logger)
      @hot_reload_manager = HotReloadManager.new(self, @logger)
      @plugins = PluginRegistry.new(logger: @logger)
      @restart_manager.attach(self)
      @slash_commands = {}
      @running = false
      @commands = {}
      @active_record = nil

      setup_event_handlers
    end

    def restart!(command: nil, env: {})
      @restart_manager.restart!(command: command, env: env)
    end

    def enable_active_record(database_url: nil, **options)
      @active_record = ActiveRecordSystem.new(logger: @logger)
      @active_record.connect(database_url: database_url, **options)
      @active_record
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
      builder = CommandBuilder.new(name, description, type: options[:type] || 1)
      builder.dm_allowed(options[:dm_permission]) if options.key?(:dm_permission)
      builder.default_permissions(options[:default_member_permissions]) if options[:default_member_permissions]
      builder.nsfw(options[:nsfw]) if options[:nsfw]

      block.call(builder) if block

      register_application_command(builder.build, name: name, guild_id: options[:guild_id])
    end

    # Register a context menu command (user or message)
    # @param type [Symbol] :user or :message
    # @param name [String] Command name
    # @param options [Hash] Command options
    # @yield [Interaction] Handler block
    # @return [ApplicationCommand] Registered command
    def context_menu(type:, name:, **options, &block)
      cmd_type = type == :user ? 2 : 3
      builder = CommandBuilder.new(name, '', type: cmd_type)
      builder.dm_allowed(options[:dm_permission]) if options.key?(:dm_permission)
      builder.default_permissions(options[:default_member_permissions]) if options[:default_member_permissions]
      builder.nsfw(options[:nsfw]) if options[:nsfw]
      builder.handler(&block) if block

      register_application_command(builder.build, name: name, guild_id: options[:guild_id])
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
      install_signal_handlers

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

    # Create a guild
    # @param name [String] Guild name
    # @param options [Hash] Optional guild creation payload
    # @return [Guild] Created guild
    def create_guild(name:, **options)
      payload = { name: name }.merge(options).compact
      data = @rest.post('/guilds', body: payload)
      Guild.new(data)
    end

    # Modify a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @param reason [String, nil] Audit log reason
    # @param options [Hash] Guild modification payload
    # @return [Guild] Updated guild
    def modify_guild(guild_id, reason: nil, **options)
      data = @rest.patch("/guilds/#{guild_id}", body: options.compact, headers: audit_log_headers(reason))
      Guild.new(data)
    end

    # Delete a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @return [void]
    def delete_guild(guild_id)
      @rest.delete("/guilds/#{guild_id}")
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

    # Crosspost a message in an announcement channel
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @return [Message] Crossposted message
    def crosspost_message(channel_id, message_id)
      data = @rest.post("/channels/#{channel_id}/messages/#{message_id}/crosspost")
      Message.new(data)
    end

    # Get messages from a channel with pagination
    # @param channel_id [String, Snowflake] Channel ID
    # @param limit [Integer] Max messages to fetch (1-100, default 50)
    # @param before [String, Snowflake] Get messages before this ID
    # @param after [String, Snowflake] Get messages after this ID
    # @param around [String, Snowflake] Get messages around this ID
    # @return [Array<Message>] Messages
    def channel_messages(channel_id, limit: 50, before: nil, after: nil, around: nil)
      params = { limit: limit }
      params[:before] = before.to_s if before
      params[:after] = after.to_s if after
      params[:around] = around.to_s if around

      data = @rest.get("/channels/#{channel_id}/messages", params: params)
      data.map { |msg| Message.new(msg) }
    end

    # Get a single message from a channel
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @return [Message, nil] Message or nil
    def channel_message(channel_id, message_id)
      data = @rest.get("/channels/#{channel_id}/messages/#{message_id}")
      Message.new(data)
    rescue RestClient::NotFoundError
      nil
    end

    # Add a recipient to a group DM
    # @param channel_id [String, Snowflake] Group DM channel ID
    # @param user_id [String, Snowflake] User ID
    # @param access_token [String] OAuth2 access token with gdm.join scope
    # @param nick [String, nil] Nickname for the recipient in the group DM
    # @return [void]
    def add_group_dm_recipient(channel_id, user_id, access_token:, nick: nil)
      payload = { access_token: access_token, nick: nick }.compact
      @rest.put("/channels/#{channel_id}/recipients/#{user_id}", body: payload)
    end

    # Remove a recipient from a group DM
    # @param channel_id [String, Snowflake] Group DM channel ID
    # @param user_id [String, Snowflake] User ID
    # @return [void]
    def remove_group_dm_recipient(channel_id, user_id)
      @rest.delete("/channels/#{channel_id}/recipients/#{user_id}")
    end

    # Trigger typing indicator for a channel
    # @param channel_id [String, Snowflake] Channel ID
    # @return [void]
    def trigger_typing(channel_id)
      @rest.post("/channels/#{channel_id}/typing")
    end

    # Get pinned messages for a channel
    # @param channel_id [String, Snowflake] Channel ID
    # @return [Array<Message>] Pinned messages
    def pinned_messages(channel_id)
      data = @rest.get("/channels/#{channel_id}/pins")
      data.map { |message| Message.new(message) }
    end

    # Pin a channel message
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @param reason [String, nil] Audit log reason
    # @return [void]
    def pin_message(channel_id, message_id, reason: nil)
      @rest.put("/channels/#{channel_id}/pins/#{message_id}", headers: audit_log_headers(reason))
    end

    # Unpin a channel message
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @param reason [String, nil] Audit log reason
    # @return [void]
    def unpin_message(channel_id, message_id, reason: nil)
      @rest.delete("/channels/#{channel_id}/pins/#{message_id}", headers: audit_log_headers(reason))
    end

    # Edit a channel permission overwrite
    # @param channel_id [String, Snowflake] Channel ID
    # @param overwrite_id [String, Snowflake] Role or member ID
    # @param allow [Integer, String] Allowed permissions bitfield
    # @param deny [Integer, String] Denied permissions bitfield
    # @param type [Integer] 0 for role, 1 for member
    # @param reason [String, nil] Audit log reason
    # @return [void]
    def edit_channel_permissions(channel_id, overwrite_id, allow:, deny:, type:, reason: nil)
      payload = {
        allow: allow.to_s,
        deny: deny.to_s,
        type: type
      }
      @rest.put("/channels/#{channel_id}/permissions/#{overwrite_id}", body: payload, headers: audit_log_headers(reason))
    end

    # Delete a channel permission overwrite
    # @param channel_id [String, Snowflake] Channel ID
    # @param overwrite_id [String, Snowflake] Role or member overwrite ID
    # @param reason [String, nil] Audit log reason
    # @return [void]
    def delete_channel_permission(channel_id, overwrite_id, reason: nil)
      @rest.delete("/channels/#{channel_id}/permissions/#{overwrite_id}", headers: audit_log_headers(reason))
    end

    # Get invites for a channel
    # @param channel_id [String, Snowflake] Channel ID
    # @return [Array<Hash>] Invite payloads
    def channel_invites(channel_id)
      @rest.get("/channels/#{channel_id}/invites")
    end

    # Create a channel invite
    # @param channel_id [String, Snowflake] Channel ID
    # @param reason [String, nil] Audit log reason
    # @yield [InviteBuilder] Optional invite builder block
    # @return [Hash] Invite payload
    def create_channel_invite(channel_id, reason: nil, **options, &block)
      builder = InviteBuilder.new
      options.each do |key, value|
        builder.public_send(key, value) if builder.respond_to?(key)
      end
      block.call(builder) if block

      @rest.post("/channels/#{channel_id}/invites", body: builder.to_h, headers: audit_log_headers(reason))
    end

    # Follow an announcement channel into a target channel
    # @param channel_id [String, Snowflake] Source announcement channel ID
    # @param webhook_channel_id [String, Snowflake] Destination channel ID
    # @return [Hash] Followed channel response
    def follow_news_channel(channel_id, webhook_channel_id)
      @rest.post("/channels/#{channel_id}/followers", body: { webhook_channel_id: webhook_channel_id.to_s })
    end

    # Start a thread from an existing message
    # @param channel_id [String, Snowflake] Parent channel ID
    # @param message_id [String, Snowflake] Message ID
    # @param name [String] Thread name
    # @param auto_archive_duration [Integer, nil] Auto archive duration in minutes
    # @param rate_limit_per_user [Integer, nil] Thread slowmode
    # @return [Channel] Created thread
    def start_thread_from_message(channel_id, message_id, name:, auto_archive_duration: nil, rate_limit_per_user: nil)
      payload = {
        name: name,
        auto_archive_duration: auto_archive_duration,
        rate_limit_per_user: rate_limit_per_user
      }.compact
      data = @rest.post("/channels/#{channel_id}/messages/#{message_id}/threads", body: payload)
      Channel.new(data)
    end

    # Start a thread without a seed message
    # @param channel_id [String, Snowflake] Parent channel ID
    # @param name [String] Thread name
    # @param type [Integer, nil] Thread type
    # @param auto_archive_duration [Integer, nil] Auto archive duration in minutes
    # @param invitable [Boolean, nil] Whether non-moderators can add users
    # @param rate_limit_per_user [Integer, nil] Thread slowmode
    # @return [Channel] Created thread
    def start_thread(channel_id, name:, type: nil, auto_archive_duration: nil, invitable: nil, rate_limit_per_user: nil)
      payload = {
        name: name,
        type: type,
        auto_archive_duration: auto_archive_duration,
        invitable: invitable,
        rate_limit_per_user: rate_limit_per_user
      }.compact
      data = @rest.post("/channels/#{channel_id}/threads", body: payload)
      Channel.new(data)
    end

    # Join a thread
    # @param thread_id [String, Snowflake] Thread channel ID
    # @return [void]
    def join_thread(thread_id)
      @rest.put("/channels/#{thread_id}/thread-members/@me")
    end

    # Add a user to a thread
    # @param thread_id [String, Snowflake] Thread channel ID
    # @param user_id [String, Snowflake] User ID
    # @return [void]
    def add_thread_member(thread_id, user_id)
      @rest.put("/channels/#{thread_id}/thread-members/#{user_id}")
    end

    # Leave a thread
    # @param thread_id [String, Snowflake] Thread channel ID
    # @return [void]
    def leave_thread(thread_id)
      @rest.delete("/channels/#{thread_id}/thread-members/@me")
    end

    # Remove a user from a thread
    # @param thread_id [String, Snowflake] Thread channel ID
    # @param user_id [String, Snowflake] User ID
    # @return [void]
    def remove_thread_member(thread_id, user_id)
      @rest.delete("/channels/#{thread_id}/thread-members/#{user_id}")
    end

    # Get a specific thread member
    # @param thread_id [String, Snowflake] Thread channel ID
    # @param user_id [String, Snowflake] User ID
    # @param with_member [Boolean] Include member object when available
    # @return [Hash, nil] Thread member payload
    def thread_member(thread_id, user_id, with_member: false)
      @rest.get("/channels/#{thread_id}/thread-members/#{user_id}", params: { with_member: with_member })
    rescue RestClient::NotFoundError
      nil
    end

    # List members in a thread
    # @param thread_id [String, Snowflake] Thread channel ID
    # @param with_member [Boolean] Include member objects when available
    # @param after [String, Snowflake, nil] Cursor
    # @param limit [Integer, nil] Max results
    # @return [Array<Hash>] Thread member payloads
    def thread_members(thread_id, with_member: false, after: nil, limit: nil)
      params = { with_member: with_member }
      params[:after] = after.to_s if after
      params[:limit] = limit if limit
      @rest.get("/channels/#{thread_id}/thread-members", params: params)
    end

    # List archived threads for a channel
    # @param channel_id [String, Snowflake] Parent channel ID
    # @param scope [Symbol] :public, :private, or :joined_private
    # @param before [Time, String, nil] ISO8601 timestamp cursor
    # @param limit [Integer, nil] Max threads to return
    # @return [Hash] Archived thread response
    def archived_threads(channel_id, scope: :public, before: nil, limit: nil)
      path = case scope
             when :public then "/channels/#{channel_id}/threads/archived/public"
             when :private then "/channels/#{channel_id}/threads/archived/private"
             when :joined_private then "/channels/#{channel_id}/users/@me/threads/archived/private"
             else
               raise ArgumentError, "Unknown archived thread scope: #{scope}"
             end

      params = {}
      params[:before] = before.is_a?(Time) ? before.iso8601 : before if before
      params[:limit] = limit if limit
      @rest.get(path, params: params)
    end

    # Enable scalable REST client (queue-based rate limiting)
    # @param proxy [Hash] Optional proxy configuration
    # @return [void]
    def enable_scalable_rest(proxy: nil)
      @logger.info('Enabling scalable REST client')
      @scalable_rest = ScalableRestClient.new(@config, @logger, proxy: proxy)
      @scalable_rest.start
      configure_entity_apis(@scalable_rest)
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

    # === Message Reactions ===

    # Add a reaction to a message
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @param emoji [String, Emoji] Emoji (unicode or name:id format)
    # @return [void]
    def add_reaction(channel_id, message_id, emoji)
      emoji_str = emoji.respond_to?(:id) ? "#{emoji.name}:#{emoji.id}" : emoji.to_s
      @rest.put("/channels/#{channel_id}/messages/#{message_id}/reactions/#{CGI.escape(emoji_str)}/@me")
    end

    # Remove a reaction from a message
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @param emoji [String, Emoji] Emoji
    # @param user_id [String, Snowflake] User ID (default: @me)
    # @return [void]
    def remove_reaction(channel_id, message_id, emoji, user_id: '@me')
      emoji_str = emoji.respond_to?(:id) ? "#{emoji.name}:#{emoji.id}" : emoji.to_s
      @rest.delete("/channels/#{channel_id}/messages/#{message_id}/reactions/#{CGI.escape(emoji_str)}/#{user_id}")
    end

    # Get reactions for a message
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @param emoji [String, Emoji] Emoji filter
    # @param limit [Integer] Max users to return (1-100, default 25)
    # @param after [String, Snowflake, nil] Cursor for pagination
    # @return [Array<User>] Users who reacted
    def get_reactions(channel_id, message_id, emoji, limit: 25, after: nil)
      emoji_str = emoji.respond_to?(:id) ? "#{emoji.name}:#{emoji.id}" : emoji.to_s
      params = { limit: limit }
      params[:after] = after.to_s if after
      data = @rest.get("/channels/#{channel_id}/messages/#{message_id}/reactions/#{CGI.escape(emoji_str)}", params: params)
      data.map { |u| User.new(u) }
    end

    # Remove all reactions from a message
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @return [void]
    def remove_all_reactions(channel_id, message_id)
      @rest.delete("/channels/#{channel_id}/messages/#{message_id}/reactions")
    end

    # === Guild Members ===

    # Get a guild member
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @return [Member, nil] Member or nil
    def guild_member(guild_id, user_id)
      data = @rest.get("/guilds/#{guild_id}/members/#{user_id}")
      Member.new(data.merge('guild_id' => guild_id.to_s))
    rescue RestClient::NotFoundError
      nil
    end

    # List guild members with pagination
    # @param guild_id [String, Snowflake] Guild ID
    # @param limit [Integer] Max members (1-1000, default 100)
    # @param after [String, Snowflake] Get members after this user ID
    # @return [Array<Member>] Members
    def guild_members(guild_id, limit: 100, after: nil)
      params = { limit: limit }
      params[:after] = after.to_s if after
      data = @rest.get("/guilds/#{guild_id}/members", params: params)
      data.map { |m| Member.new(m.merge('guild_id' => guild_id.to_s)) }
    end

    # Search guild members by query
    # @param guild_id [String, Snowflake] Guild ID
    # @param query [String] Search query (username/nickname prefix)
    # @param limit [Integer] Max results (1-100, default 25)
    # @return [Array<Member>] Matching members
    def search_guild_members(guild_id, query, limit: 25)
      params = { query: query, limit: limit }
      data = @rest.get("/guilds/#{guild_id}/members/search", params: params)
      data.map { |m| Member.new(m.merge('guild_id' => guild_id.to_s)) }
    end

    # Modify a guild member
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @param options [Hash] Options to modify (nick, roles, mute, deaf, channel_id)
    # @return [Member] Updated member
    def modify_guild_member(guild_id, user_id, **options)
      payload = options.slice(:nick, :roles, :mute, :deaf, :channel_id, :communication_disabled_until)
      data = @rest.patch("/guilds/#{guild_id}/members/#{user_id}", body: payload)
      Member.new(data.merge('guild_id' => guild_id.to_s))
    end

    # Add a member to a guild through OAuth2
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @param access_token [String] User OAuth2 access token
    # @param options [Hash] Optional member settings
    # @return [Hash] Discord add-member response
    def add_guild_member(guild_id, user_id, access_token:, **options)
      payload = {
        access_token: access_token,
        nick: options[:nick],
        roles: options[:roles],
        mute: options[:mute],
        deaf: options[:deaf]
      }.compact
      @rest.put("/guilds/#{guild_id}/members/#{user_id}", body: payload)
    end

    # Modify the current bot member in a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @param nick [String, nil] New nickname
    # @param reason [String, nil] Audit log reason
    # @return [Member] Updated member
    def modify_current_member(guild_id, nick: nil, reason: nil)
      data = @rest.patch("/guilds/#{guild_id}/members/@me", body: { nick: nick }.compact, headers: audit_log_headers(reason))
      Member.new(data.merge('guild_id' => guild_id.to_s))
    end

    # Modify the current bot nickname in a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @param nick [String, nil] New nickname
    # @param reason [String, nil] Audit log reason
    # @return [Hash] Discord nickname response
    def modify_current_user_nick(guild_id, nick: nil, reason: nil)
      @rest.patch("/guilds/#{guild_id}/members/@me/nick", body: { nick: nick }.compact, headers: audit_log_headers(reason))
    end

    # Add role to guild member
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @param role_id [String, Snowflake] Role ID
    # @param reason [String] Audit log reason
    # @return [void]
    def add_guild_member_role(guild_id, user_id, role_id, reason: nil)
      headers = reason ? { 'X-Audit-Log-Reason' => CGI.escape(reason) } : {}
      @rest.put("/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}", headers: headers)
    end

    # Remove role from guild member
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @param role_id [String, Snowflake] Role ID
    # @param reason [String] Audit log reason
    # @return [void]
    def remove_guild_member_role(guild_id, user_id, role_id, reason: nil)
      headers = reason ? { 'X-Audit-Log-Reason' => CGI.escape(reason) } : {}
      @rest.delete("/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}", headers: headers)
    end

    # Remove guild member (kick)
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @param reason [String] Audit log reason
    # @return [void]
    def remove_guild_member(guild_id, user_id, reason: nil)
      headers = reason ? { 'X-Audit-Log-Reason' => CGI.escape(reason) } : {}
      @rest.delete("/guilds/#{guild_id}/members/#{user_id}", headers: headers)
    end

    # === Guild Roles ===

    # Get guild roles
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Role>] Roles
    def guild_roles(guild_id)
      data = @rest.get("/guilds/#{guild_id}/roles")
      data.map { |r| Role.new(r.merge('guild_id' => guild_id.to_s)) }
    end

    # Create guild role
    # @param guild_id [String, Snowflake] Guild ID
    # @param name [String] Role name
    # @param options [Hash] Optional settings (permissions, color, hoist, mentionable)
    # @return [Role] Created role
    def create_guild_role(guild_id, name:, reason: nil, **options)
      payload = { name: name }.merge(options.slice(:permissions, :color, :hoist, :mentionable, :icon, :unicode_emoji))
      data = @rest.post("/guilds/#{guild_id}/roles", body: payload, headers: audit_log_headers(reason))
      Role.new(data.merge('guild_id' => guild_id.to_s))
    end

    # Modify guild role
    # @param guild_id [String, Snowflake] Guild ID
    # @param role_id [String, Snowflake] Role ID
    # @param options [Hash] Settings to modify
    # @return [Role] Updated role
    def modify_guild_role(guild_id, role_id, reason: nil, **options)
      payload = options.slice(:name, :permissions, :color, :hoist, :mentionable, :icon, :unicode_emoji)
      data = @rest.patch("/guilds/#{guild_id}/roles/#{role_id}", body: payload, headers: audit_log_headers(reason))
      Role.new(data.merge('guild_id' => guild_id.to_s))
    end

    # Modify guild role positions
    # @param guild_id [String, Snowflake] Guild ID
    # @param positions [Array<Hash>] Array of { id:, position: }
    # @param reason [String, nil] Audit log reason
    # @return [Array<Role>] Updated role ordering
    def modify_guild_role_positions(guild_id, positions, reason: nil)
      payload = positions.map do |position|
        { id: (position[:id] || position['id']).to_s, position: position[:position] || position['position'] }
      end
      data = @rest.patch("/guilds/#{guild_id}/roles", body: payload, headers: audit_log_headers(reason))
      data.map { |role| Role.new(role.merge('guild_id' => guild_id.to_s)) }
    end

    # Delete guild role
    # @param guild_id [String, Snowflake] Guild ID
    # @param role_id [String, Snowflake] Role ID
    # @param reason [String] Audit log reason
    # @return [void]
    def delete_guild_role(guild_id, role_id, reason: nil)
      headers = reason ? { 'X-Audit-Log-Reason' => CGI.escape(reason) } : {}
      @rest.delete("/guilds/#{guild_id}/roles/#{role_id}", headers: headers)
    end

    # === Guild Bans ===

    # Get guild bans
    # @param guild_id [String, Snowflake] Guild ID
    # @param limit [Integer] Max bans (1-1000, default 100)
    # @param before [String, Snowflake, nil] Cursor for pagination
    # @param after [String, Snowflake, nil] Cursor for pagination
    # @return [Array<Hash>] Bans (user + reason data)
    def guild_bans(guild_id, limit: 100, before: nil, after: nil)
      params = { limit: limit }
      params[:before] = before.to_s if before
      params[:after] = after.to_s if after
      data = @rest.get("/guilds/#{guild_id}/bans", params: params)
      data.map { |b| { user: User.new(b['user']), reason: b['reason'] } }
    end

    # Get a specific guild ban
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @return [Hash, nil] Ban data or nil
    def guild_ban(guild_id, user_id)
      data = @rest.get("/guilds/#{guild_id}/bans/#{user_id}")
      { user: User.new(data['user']), reason: data['reason'] }
    rescue RestClient::NotFoundError
      nil
    end

    # Create guild ban
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @param delete_message_days [Integer] Days of messages to delete (0-7)
    # @param reason [String] Audit log reason
    # @return [void]
    def create_guild_ban(guild_id, user_id, delete_message_days: nil, reason: nil)
      payload = {}
      payload[:delete_message_days] = delete_message_days if delete_message_days
      headers = reason ? { 'X-Audit-Log-Reason' => CGI.escape(reason) } : {}
      @rest.put("/guilds/#{guild_id}/bans/#{user_id}", body: payload, headers: headers)
    end

    # Remove guild ban (unban)
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @param reason [String] Audit log reason
    # @return [void]
    def remove_guild_ban(guild_id, user_id, reason: nil)
      headers = reason ? { 'X-Audit-Log-Reason' => CGI.escape(reason) } : {}
      @rest.delete("/guilds/#{guild_id}/bans/#{user_id}", headers: headers)
    end

    # === Webhooks ===

    # Create a webhook
    # @param channel_id [String, Snowflake] Channel ID
    # @param name [String] Webhook name
    # @param avatar [String] Base64-encoded avatar image (optional)
    # @return [Webhook] Webhook data
    def create_webhook(channel_id, name:, avatar: nil, reason: nil)
      payload = { name: name }
      payload[:avatar] = avatar if avatar
      Webhook.new(@rest.post("/channels/#{channel_id}/webhooks", body: payload, headers: audit_log_headers(reason)))
    end

    # Get channel webhooks
    # @param channel_id [String, Snowflake] Channel ID
    # @return [Array<Webhook>] Webhooks
    def channel_webhooks(channel_id)
      @rest.get("/channels/#{channel_id}/webhooks").map { |hook| Webhook.new(hook) }
    end

    # Get guild webhooks
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Webhook>] Webhooks
    def guild_webhooks(guild_id)
      @rest.get("/guilds/#{guild_id}/webhooks").map { |hook| Webhook.new(hook) }
    end

    # Execute webhook
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token
    # @param content [String] Message content
    # @param options [Hash] Options (username, avatar_url, embeds, etc.)
    # @option options [Boolean] :wait Return the created message
    # @option options [String, Snowflake] :thread_id Execute in a thread
    # @return [Message, nil]
    def execute_webhook(webhook_id, token, content = nil, **options)
      params = {}
      params[:wait] = options[:wait] unless options[:wait].nil?
      params[:thread_id] = options[:thread_id].to_s if options[:thread_id]
      payload = { content: content }.merge(options.slice(:username, :avatar_url, :embeds, :components, :allowed_mentions, :tts))
      response = @rest.post("/webhooks/#{webhook_id}/#{token}", body: payload, params: params)
      response.is_a?(Hash) ? Message.new(response) : nil
    end

    # Delete a webhook
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token (optional, for webhook-owned deletes)
    # @return [void]
    def delete_webhook(webhook_id, token: nil)
      path = token ? "/webhooks/#{webhook_id}/#{token}" : "/webhooks/#{webhook_id}"
      @rest.delete(path)
    end

    # Get a webhook by ID
    # @param webhook_id [String, Snowflake] Webhook ID
    # @return [Webhook, nil] Webhook payload
    def webhook(webhook_id)
      Webhook.new(@rest.get("/webhooks/#{webhook_id}"))
    rescue RestClient::NotFoundError
      nil
    end

    # Get a webhook by ID and token
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token
    # @return [Webhook, nil] Webhook payload
    def webhook_with_token(webhook_id, token)
      Webhook.new(@rest.get("/webhooks/#{webhook_id}/#{token}"))
    rescue RestClient::NotFoundError
      nil
    end

    # Modify a webhook
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param name [String, nil] New webhook name
    # @param avatar [String, nil] Base64 avatar data
    # @param channel_id [String, Snowflake, nil] New channel ID
    # @return [Webhook] Updated webhook payload
    def modify_webhook(webhook_id, name: nil, avatar: nil, channel_id: nil, reason: nil)
      payload = { name: name, avatar: avatar, channel_id: channel_id&.to_s }.compact
      Webhook.new(@rest.patch("/webhooks/#{webhook_id}", body: payload, headers: audit_log_headers(reason)))
    end

    # Modify a webhook using its token
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token
    # @param name [String, nil] New webhook name
    # @param avatar [String, nil] Base64 avatar data
    # @return [Webhook] Updated webhook payload
    def modify_webhook_with_token(webhook_id, token, name: nil, avatar: nil)
      payload = { name: name, avatar: avatar }.compact
      Webhook.new(@rest.patch("/webhooks/#{webhook_id}/#{token}", body: payload))
    end

    # Execute a Slack-compatible webhook
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token
    # @param payload [Hash] Slack webhook payload
    # @return [Object] API response
    def execute_slack_webhook(webhook_id, token, payload)
      @rest.post("/webhooks/#{webhook_id}/#{token}/slack", body: payload)
    end

    # Execute a GitHub-compatible webhook
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token
    # @param payload [Hash] GitHub webhook payload
    # @return [Object] API response
    def execute_github_webhook(webhook_id, token, payload)
      @rest.post("/webhooks/#{webhook_id}/#{token}/github", body: payload)
    end

    # Get a webhook message
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token
    # @param message_id [String, Snowflake] Message ID
    # @param thread_id [String, Snowflake, nil] Thread channel ID
    # @return [Message, nil] Webhook message
    def webhook_message(webhook_id, token, message_id, thread_id: nil)
      params = {}
      params[:thread_id] = thread_id.to_s if thread_id
      data = @rest.get("/webhooks/#{webhook_id}/#{token}/messages/#{message_id}", params: params)
      Message.new(data)
    rescue RestClient::NotFoundError
      nil
    end

    # Edit a webhook message
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token
    # @param message_id [String, Snowflake] Message ID
    # @param thread_id [String, Snowflake, nil] Thread channel ID
    # @param content [String, nil] New content
    # @param options [Hash] Additional edit payload
    # @return [Message] Updated message
    def edit_webhook_message(webhook_id, token, message_id, thread_id: nil, content: nil, **options)
      params = {}
      params[:thread_id] = thread_id.to_s if thread_id
      payload = { content: content }.merge(options).compact
      data = @rest.patch("/webhooks/#{webhook_id}/#{token}/messages/#{message_id}", body: payload, params: params)
      Message.new(data)
    end

    # Delete a webhook message
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token
    # @param message_id [String, Snowflake] Message ID
    # @param thread_id [String, Snowflake, nil] Thread channel ID
    # @return [void]
    def delete_webhook_message(webhook_id, token, message_id, thread_id: nil)
      params = {}
      params[:thread_id] = thread_id.to_s if thread_id
      @rest.delete("/webhooks/#{webhook_id}/#{token}/messages/#{message_id}", params: params)
    end

    # === Channel Management ===

    # Get guild channels
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Channel>] Channels
    def guild_channels(guild_id)
      data = @rest.get("/guilds/#{guild_id}/channels")
      data.map { |c| Channel.new(c) }
    end

    # Get a guild preview
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Hash, nil] Guild preview payload
    def guild_preview(guild_id)
      @rest.get("/guilds/#{guild_id}/preview")
    rescue RestClient::NotFoundError
      nil
    end

    # Get the expected prune count for a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @param days [Integer] Inactive days threshold
    # @param include_roles [Array<String, Snowflake>] Optional role IDs
    # @return [Integer, nil] Number of prunable members
    def guild_prune_count(guild_id, days:, include_roles: nil)
      params = { days: days }
      params[:include_roles] = Array(include_roles).map(&:to_s).join(',') if include_roles
      @rest.get("/guilds/#{guild_id}/prune", params: params)['pruned']
    end

    # Begin a guild prune
    # @param guild_id [String, Snowflake] Guild ID
    # @param days [Integer] Inactive days threshold
    # @param compute_prune_count [Boolean] Whether to include the prune count
    # @param include_roles [Array<String, Snowflake>] Optional role IDs
    # @param reason [String, nil] Audit log reason
    # @return [Integer, nil] Number of pruned members when requested
    def begin_guild_prune(guild_id, days:, compute_prune_count: true, include_roles: nil, reason: nil)
      payload = { days: days, compute_prune_count: compute_prune_count }
      payload[:include_roles] = Array(include_roles).map(&:to_s) if include_roles
      response = @rest.post("/guilds/#{guild_id}/prune", body: payload, headers: audit_log_headers(reason))
      response && response['pruned']
    end

    # Get voice regions for a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Hash>] Voice regions
    def guild_voice_regions(guild_id)
      @rest.get("/guilds/#{guild_id}/regions")
    end

    # Get active invites for a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Hash>] Invite payloads
    def guild_invites(guild_id)
      @rest.get("/guilds/#{guild_id}/invites")
    end

    # Get integrations for a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Integration>] Integration payloads
    def guild_integrations(guild_id)
      @rest.get("/guilds/#{guild_id}/integrations").map { |integration| Integration.new(integration.merge('guild_id' => guild_id.to_s)) }
    end

    # Delete a guild integration
    # @param guild_id [String, Snowflake] Guild ID
    # @param integration_id [String, Snowflake] Integration ID
    # @param reason [String, nil] Audit log reason
    # @return [void]
    def delete_guild_integration(guild_id, integration_id, reason: nil)
      @rest.delete("/guilds/#{guild_id}/integrations/#{integration_id}", headers: audit_log_headers(reason))
    end

    # Get guild widget settings
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Hash, nil] Widget settings
    def guild_widget_settings(guild_id)
      @rest.get("/guilds/#{guild_id}/widget")
    rescue RestClient::NotFoundError
      nil
    end

    # Modify guild widget settings
    # @param guild_id [String, Snowflake] Guild ID
    # @param enabled [Boolean, nil] Whether widget is enabled
    # @param channel_id [String, Snowflake, nil] Widget channel ID
    # @param reason [String, nil] Audit log reason
    # @return [Hash] Updated widget settings
    def modify_guild_widget(guild_id, enabled: nil, channel_id: nil, reason: nil)
      payload = { enabled: enabled, channel_id: channel_id&.to_s }.compact
      @rest.patch("/guilds/#{guild_id}/widget", body: payload, headers: audit_log_headers(reason))
    end

    # Get guild widget data
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Hash, nil] Widget payload
    def guild_widget(guild_id)
      @rest.get("/guilds/#{guild_id}/widget.json")
    rescue RestClient::NotFoundError
      nil
    end

    # Get a guild vanity URL
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Hash, nil] Vanity URL payload
    def guild_vanity_url(guild_id)
      @rest.get("/guilds/#{guild_id}/vanity-url")
    rescue RestClient::NotFoundError
      nil
    end

    # Build a guild widget image URL
    # @param guild_id [String, Snowflake] Guild ID
    # @param style [String, nil] Widget image style
    # @return [String] Widget image URL
    def guild_widget_image(guild_id, style: nil)
      url = "https://discord.com/api/guilds/#{guild_id}/widget.png"
      style ? "#{url}?style=#{CGI.escape(style)}" : url
    end

    # Get a guild welcome screen
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Hash, nil] Welcome screen payload
    def guild_welcome_screen(guild_id)
      @rest.get("/guilds/#{guild_id}/welcome-screen")
    rescue RestClient::NotFoundError
      nil
    end

    # Modify a guild welcome screen
    # @param guild_id [String, Snowflake] Guild ID
    # @param enabled [Boolean, nil] Whether enabled
    # @param welcome_channels [Array<Hash>, nil] Welcome channel configuration
    # @param description [String, nil] Welcome description
    # @param reason [String, nil] Audit log reason
    # @return [Hash] Updated welcome screen payload
    def modify_guild_welcome_screen(guild_id, enabled: nil, welcome_channels: nil, description: nil, reason: nil)
      payload = {
        enabled: enabled,
        welcome_channels: welcome_channels,
        description: description
      }.compact
      @rest.patch("/guilds/#{guild_id}/welcome-screen", body: payload, headers: audit_log_headers(reason))
    end

    # Get guild onboarding
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Hash, nil] Onboarding payload
    def guild_onboarding(guild_id)
      @rest.get("/guilds/#{guild_id}/onboarding")
    rescue RestClient::NotFoundError
      nil
    end

    # Modify guild onboarding
    # @param guild_id [String, Snowflake] Guild ID
    # @param options [Hash] Raw onboarding payload
    # @return [Hash] Updated onboarding payload
    def modify_guild_onboarding(guild_id, **options)
      @rest.put("/guilds/#{guild_id}/onboarding", body: options)
    end

    # Get audit log entries for a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake, nil] Filter by acting user
    # @param action_type [Integer, nil] Filter by action type
    # @param before [String, Snowflake, nil] Pagination cursor
    # @param after [String, Snowflake, nil] Pagination cursor
    # @param limit [Integer, nil] Max entries
    # @return [AuditLog] Audit log payload
    def guild_audit_log(guild_id, user_id: nil, action_type: nil, before: nil, after: nil, limit: nil)
      params = {
        user_id: user_id&.to_s,
        action_type: action_type,
        before: before&.to_s,
        after: after&.to_s,
        limit: limit
      }.compact
      AuditLog.new(@rest.get("/guilds/#{guild_id}/audit-logs", params: params))
    end

    # List scheduled events for a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @param with_user_count [Boolean] Include subscriber counts
    # @return [Array<GuildScheduledEvent>] Scheduled events
    def guild_scheduled_events(guild_id, with_user_count: false)
      data = @rest.get("/guilds/#{guild_id}/scheduled-events", params: { with_user_count: with_user_count })
      data.map { |event| GuildScheduledEvent.new(event) }
    end

    # Get a specific scheduled event
    # @param guild_id [String, Snowflake] Guild ID
    # @param event_id [String, Snowflake] Event ID
    # @param with_user_count [Boolean] Include subscriber count
    # @return [GuildScheduledEvent, nil] Scheduled event
    def guild_scheduled_event(guild_id, event_id, with_user_count: false)
      data = @rest.get("/guilds/#{guild_id}/scheduled-events/#{event_id}", params: { with_user_count: with_user_count })
      GuildScheduledEvent.new(data)
    rescue RestClient::NotFoundError
      nil
    end

    # Create a scheduled event
    # @param guild_id [String, Snowflake] Guild ID
    # @param reason [String, nil] Audit log reason
    # @param options [Hash] Scheduled event payload
    # @return [GuildScheduledEvent] Created event
    def create_guild_scheduled_event(guild_id, reason: nil, **options)
      data = @rest.post("/guilds/#{guild_id}/scheduled-events", body: options.compact, headers: audit_log_headers(reason))
      GuildScheduledEvent.new(data)
    end

    # Modify a scheduled event
    # @param guild_id [String, Snowflake] Guild ID
    # @param event_id [String, Snowflake] Event ID
    # @param reason [String, nil] Audit log reason
    # @param options [Hash] Scheduled event payload
    # @return [GuildScheduledEvent] Updated event
    def modify_guild_scheduled_event(guild_id, event_id, reason: nil, **options)
      data = @rest.patch("/guilds/#{guild_id}/scheduled-events/#{event_id}", body: options.compact, headers: audit_log_headers(reason))
      GuildScheduledEvent.new(data)
    end

    # Delete a scheduled event
    # @param guild_id [String, Snowflake] Guild ID
    # @param event_id [String, Snowflake] Event ID
    # @return [void]
    def delete_guild_scheduled_event(guild_id, event_id)
      @rest.delete("/guilds/#{guild_id}/scheduled-events/#{event_id}")
    end

    # List users subscribed to a scheduled event
    # @param guild_id [String, Snowflake] Guild ID
    # @param event_id [String, Snowflake] Event ID
    # @param limit [Integer, nil] Max users
    # @param with_member [Boolean] Include member objects
    # @param before [String, Snowflake, nil] Pagination cursor
    # @param after [String, Snowflake, nil] Pagination cursor
    # @return [Array<Hash>] Subscriber payloads
    def guild_scheduled_event_users(guild_id, event_id, limit: nil, with_member: false, before: nil, after: nil)
      params = {
        limit: limit,
        with_member: with_member,
        before: before&.to_s,
        after: after&.to_s
      }.compact
      @rest.get("/guilds/#{guild_id}/scheduled-events/#{event_id}/users", params: params)
    end

    # Create a stage instance
    # @param channel_id [String, Snowflake] Stage channel ID
    # @param topic [String] Stage topic
    # @param privacy_level [Integer, nil] Privacy level
    # @param send_start_notification [Boolean, nil] Send notification
    # @param guild_scheduled_event_id [String, Snowflake, nil] Associated scheduled event
    # @return [Hash] Stage instance payload
    def create_stage_instance(channel_id:, topic:, privacy_level: nil, send_start_notification: nil, guild_scheduled_event_id: nil)
      payload = {
        channel_id: channel_id.to_s,
        topic: topic,
        privacy_level: privacy_level,
        send_start_notification: send_start_notification,
        guild_scheduled_event_id: guild_scheduled_event_id&.to_s
      }.compact
      @rest.post('/stage-instances', body: payload)
    end

    # Get a stage instance
    # @param channel_id [String, Snowflake] Stage channel ID
    # @return [Hash, nil] Stage instance payload
    def stage_instance(channel_id)
      @rest.get("/stage-instances/#{channel_id}")
    rescue RestClient::NotFoundError
      nil
    end

    # Modify a stage instance
    # @param channel_id [String, Snowflake] Stage channel ID
    # @param topic [String, nil] Updated topic
    # @param privacy_level [Integer, nil] Updated privacy level
    # @return [Hash] Updated stage instance payload
    def modify_stage_instance(channel_id, topic: nil, privacy_level: nil)
      @rest.patch("/stage-instances/#{channel_id}", body: { topic: topic, privacy_level: privacy_level }.compact)
    end

    # Delete a stage instance
    # @param channel_id [String, Snowflake] Stage channel ID
    # @param reason [String, nil] Audit log reason
    # @return [void]
    def delete_stage_instance(channel_id, reason: nil)
      @rest.delete("/stage-instances/#{channel_id}", headers: audit_log_headers(reason))
    end

    # List stickers for a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Sticker>] Guild stickers
    def guild_stickers(guild_id)
      data = @rest.get("/guilds/#{guild_id}/stickers")
      data.map { |sticker| Sticker.new(sticker) }
    end

    # Get a guild sticker
    # @param guild_id [String, Snowflake] Guild ID
    # @param sticker_id [String, Snowflake] Sticker ID
    # @return [Sticker, nil] Sticker
    def guild_sticker(guild_id, sticker_id)
      data = @rest.get("/guilds/#{guild_id}/stickers/#{sticker_id}")
      Sticker.new(data)
    rescue RestClient::NotFoundError
      nil
    end

    # Get a standard sticker
    # @param sticker_id [String, Snowflake] Sticker ID
    # @return [Sticker, nil] Sticker
    def sticker(sticker_id)
      data = @rest.get("/stickers/#{sticker_id}")
      Sticker.new(data)
    rescue RestClient::NotFoundError
      nil
    end

    # List available premium sticker packs
    # @return [Hash] Sticker pack payload
    def sticker_packs
      @rest.get('/sticker-packs')
    end

    # Get guild templates
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Hash>] Template payloads
    def guild_templates(guild_id)
      @rest.get("/guilds/#{guild_id}/templates")
    end

    # Create a guild template
    # @param guild_id [String, Snowflake] Guild ID
    # @param name [String] Template name
    # @param description [String, nil] Template description
    # @return [Hash] Template payload
    def create_guild_template(guild_id, name:, description: nil)
      @rest.post("/guilds/#{guild_id}/templates", body: { name: name, description: description }.compact)
    end

    # Sync a guild template
    # @param guild_id [String, Snowflake] Guild ID
    # @param code [String] Template code
    # @return [Hash] Template payload
    def sync_guild_template(guild_id, code)
      @rest.put("/guilds/#{guild_id}/templates/#{code}")
    end

    # Modify a guild template
    # @param guild_id [String, Snowflake] Guild ID
    # @param code [String] Template code
    # @param name [String, nil] New template name
    # @param description [String, nil] New template description
    # @return [Hash] Template payload
    def modify_guild_template(guild_id, code, name: nil, description: nil)
      payload = { name: name, description: description }.compact
      @rest.patch("/guilds/#{guild_id}/templates/#{code}", body: payload)
    end

    # Delete a guild template
    # @param guild_id [String, Snowflake] Guild ID
    # @param code [String] Template code
    # @return [Hash] Deleted template payload
    def delete_guild_template(guild_id, code)
      @rest.delete("/guilds/#{guild_id}/templates/#{code}")
    end

    # Fetch a guild template by code
    # @param code [String] Template code
    # @return [Hash, nil] Template payload
    def guild_template(code)
      @rest.get("/guilds/templates/#{code}")
    rescue RestClient::NotFoundError
      nil
    end

    # Create a guild from a template
    # @param code [String] Template code
    # @param name [String] Guild name
    # @param icon [String, nil] Base64 icon data
    # @return [Guild] Created guild
    def create_guild_from_template(code, name:, icon: nil)
      data = @rest.post("/guilds/templates/#{code}", body: { name: name, icon: icon }.compact)
      Guild.new(data)
    end

    # List auto moderation rules for a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<AutoModerationRule>] Rules
    def auto_moderation_rules(guild_id)
      data = @rest.get("/guilds/#{guild_id}/auto-moderation/rules")
      data.map { |rule| AutoModerationRule.new(rule) }
    end

    # Get a specific auto moderation rule
    # @param guild_id [String, Snowflake] Guild ID
    # @param rule_id [String, Snowflake] Rule ID
    # @return [AutoModerationRule, nil] Rule
    def auto_moderation_rule(guild_id, rule_id)
      data = @rest.get("/guilds/#{guild_id}/auto-moderation/rules/#{rule_id}")
      AutoModerationRule.new(data)
    rescue RestClient::NotFoundError
      nil
    end

    # Create an auto moderation rule
    # @param guild_id [String, Snowflake] Guild ID
    # @param reason [String, nil] Audit log reason
    # @param options [Hash] Rule payload
    # @return [AutoModerationRule] Created rule
    def create_auto_moderation_rule(guild_id, reason: nil, **options)
      data = @rest.post("/guilds/#{guild_id}/auto-moderation/rules", body: options.compact, headers: audit_log_headers(reason))
      AutoModerationRule.new(data)
    end

    # Modify an auto moderation rule
    # @param guild_id [String, Snowflake] Guild ID
    # @param rule_id [String, Snowflake] Rule ID
    # @param reason [String, nil] Audit log reason
    # @param options [Hash] Rule payload
    # @return [AutoModerationRule] Updated rule
    def modify_auto_moderation_rule(guild_id, rule_id, reason: nil, **options)
      data = @rest.patch("/guilds/#{guild_id}/auto-moderation/rules/#{rule_id}", body: options.compact, headers: audit_log_headers(reason))
      AutoModerationRule.new(data)
    end

    # Delete an auto moderation rule
    # @param guild_id [String, Snowflake] Guild ID
    # @param rule_id [String, Snowflake] Rule ID
    # @param reason [String, nil] Audit log reason
    # @return [void]
    def delete_auto_moderation_rule(guild_id, rule_id, reason: nil)
      @rest.delete("/guilds/#{guild_id}/auto-moderation/rules/#{rule_id}", headers: audit_log_headers(reason))
    end

    # Get SKUs for the current application
    # @param application_id [String, Snowflake, nil] Application ID
    # @return [Array<Hash>] SKU payloads
    def skus(application_id: nil)
      app_id = application_id || application_id_for_rest
      @rest.get("/applications/#{app_id}/skus")
    end

    # Get entitlements for the current application
    # @param application_id [String, Snowflake, nil] Application ID
    # @param options [Hash] Query filters
    # @return [Array<Hash>] Entitlement payloads
    def entitlements(application_id: nil, **options)
      app_id = application_id || application_id_for_rest
      params = normalize_rest_params(options, :before, :after, :guild_id, :user_id, :limit, :exclude_ended)
      params[:sku_ids] = Array(options[:sku_ids]).map(&:to_s).join(',') if options[:sku_ids]
      @rest.get("/applications/#{app_id}/entitlements", params: params)
    end

    # Create a test entitlement
    # @param sku_id [String, Snowflake] SKU ID
    # @param owner_id [String, Snowflake] User or guild owner ID
    # @param owner_type [Integer] 1 for guild, 2 for user
    # @param application_id [String, Snowflake, nil] Application ID
    # @return [Hash] Entitlement payload
    def create_test_entitlement(sku_id:, owner_id:, owner_type:, application_id: nil)
      app_id = application_id || application_id_for_rest
      payload = { sku_id: sku_id.to_s, owner_id: owner_id.to_s, owner_type: owner_type }
      @rest.post("/applications/#{app_id}/entitlements", body: payload)
    end

    # Delete a test entitlement
    # @param entitlement_id [String, Snowflake] Entitlement ID
    # @param application_id [String, Snowflake, nil] Application ID
    # @return [void]
    def delete_test_entitlement(entitlement_id, application_id: nil)
      app_id = application_id || application_id_for_rest
      @rest.delete("/applications/#{app_id}/entitlements/#{entitlement_id}")
    end

    # Consume an entitlement
    # @param entitlement_id [String, Snowflake] Entitlement ID
    # @param application_id [String, Snowflake, nil] Application ID
    # @return [void]
    def consume_entitlement(entitlement_id, application_id: nil)
      app_id = application_id || application_id_for_rest
      @rest.post("/applications/#{app_id}/entitlements/#{entitlement_id}/consume")
    end

    # Get default soundboard sounds
    # @return [Hash] Soundboard payload
    def default_soundboard_sounds
      @rest.get('/soundboard-default-sounds')
    end

    # Get guild soundboard sounds
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Hash] Soundboard payload
    def guild_soundboard_sounds(guild_id)
      @rest.get("/guilds/#{guild_id}/soundboard-sounds")
    end

    # Get a single guild soundboard sound
    # @param guild_id [String, Snowflake] Guild ID
    # @param sound_id [String, Snowflake] Sound ID
    # @return [Hash, nil] Soundboard sound payload
    def guild_soundboard_sound(guild_id, sound_id)
      @rest.get("/guilds/#{guild_id}/soundboard-sounds/#{sound_id}")
    rescue RestClient::NotFoundError
      nil
    end

    # Create a guild soundboard sound
    # @param guild_id [String, Snowflake] Guild ID
    # @param reason [String, nil] Audit log reason
    # @param options [Hash] Soundboard payload
    # @return [Hash] Soundboard sound payload
    def create_guild_soundboard_sound(guild_id, reason: nil, **options)
      @rest.post("/guilds/#{guild_id}/soundboard-sounds", body: options.compact, headers: audit_log_headers(reason))
    end

    # Modify a guild soundboard sound
    # @param guild_id [String, Snowflake] Guild ID
    # @param sound_id [String, Snowflake] Sound ID
    # @param reason [String, nil] Audit log reason
    # @param options [Hash] Soundboard payload
    # @return [Hash] Soundboard sound payload
    def modify_guild_soundboard_sound(guild_id, sound_id, reason: nil, **options)
      @rest.patch("/guilds/#{guild_id}/soundboard-sounds/#{sound_id}", body: options.compact, headers: audit_log_headers(reason))
    end

    # Delete a guild soundboard sound
    # @param guild_id [String, Snowflake] Guild ID
    # @param sound_id [String, Snowflake] Sound ID
    # @param reason [String, nil] Audit log reason
    # @return [void]
    def delete_guild_soundboard_sound(guild_id, sound_id, reason: nil)
      @rest.delete("/guilds/#{guild_id}/soundboard-sounds/#{sound_id}", headers: audit_log_headers(reason))
    end

    # Send a soundboard sound in a voice-connected channel
    # @param channel_id [String, Snowflake] Voice channel ID
    # @param sound_id [String, Snowflake] Sound ID
    # @param source_guild_id [String, Snowflake, nil] Source guild for default/shared sounds
    # @return [void]
    def send_soundboard_sound(channel_id, sound_id:, source_guild_id: nil)
      payload = { sound_id: sound_id.to_s, source_guild_id: source_guild_id&.to_s }.compact
      @rest.post("/channels/#{channel_id}/send-soundboard-sound", body: payload)
    end

    # Create guild channel
    # @param guild_id [String, Snowflake] Guild ID
    # @param name [String] Channel name
    # @param type [Integer] Channel type (0=text, 2=voice, 4=category, etc.)
    # @param options [Hash] Optional settings
    # @return [Channel] Created channel
    def create_guild_channel(guild_id, name:, type: 0, **options)
      payload = { name: name, type: type }.merge(options.slice(:topic, :bitrate, :user_limit, :parent_id, :nsfw, :permission_overwrites, :rate_limit_per_user))
      data = @rest.post("/guilds/#{guild_id}/channels", body: payload)
      Channel.new(data)
    end

    # Modify channel
    # @param channel_id [String, Snowflake] Channel ID
    # @param options [Hash] Settings to modify
    # @return [Channel] Updated channel
    def modify_channel(channel_id, **options)
      payload = options.slice(:name, :type, :position, :topic, :nsfw, :rate_limit_per_user, :bitrate, :user_limit, :parent_id, :default_auto_archive_duration)
      data = @rest.patch("/channels/#{channel_id}", body: payload)
      Channel.new(data)
    end

    # Delete channel
    # @param channel_id [String, Snowflake] Channel ID
    # @param reason [String] Audit log reason
    # @return [Channel] Deleted channel
    def delete_channel(channel_id, reason: nil)
      headers = reason ? { 'X-Audit-Log-Reason' => CGI.escape(reason) } : {}
      data = @rest.delete("/channels/#{channel_id}", headers: headers)
      Channel.new(data)
    end

    # Bulk delete messages
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_ids [Array<String, Snowflake>] Message IDs to delete (2-100)
    # @param reason [String] Audit log reason
    # @return [void]
    def bulk_delete_messages(channel_id, message_ids, reason: nil)
      headers = reason ? { 'X-Audit-Log-Reason' => CGI.escape(reason) } : {}
      @rest.post("/channels/#{channel_id}/messages/bulk-delete", body: { messages: message_ids.map(&:to_s) }, headers: headers)
    end

    # Modify the bot user's profile
    # @param username [String, nil] New username
    # @param avatar [File, String, nil] New avatar
    # @return [User, nil] Updated user
    def modify_current_user(username: nil, avatar: nil)
      User.modify_current_user(username: username, avatar: avatar)
    end

    # Get the current user's guilds
    # @param limit [Integer] Max guilds to return
    # @param after [String, Snowflake, nil] Cursor
    # @param before [String, Snowflake, nil] Cursor
    # @param with_counts [Boolean] Include approximate counts
    # @return [Array<Hash>] Partial guild payloads
    def current_user_guilds(limit: 200, after: nil, before: nil, with_counts: false)
      User.get_current_user_guilds(limit: limit, after: after&.to_s, before: before&.to_s, with_counts: with_counts)
    end

    # Get the current user's member object in a guild
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Hash, nil] Member payload
    def current_user_guild_member(guild_id)
      User.get_current_user_guild_member(guild_id)
    end

    # Leave a guild as the current user
    # @param guild_id [String, Snowflake] Guild ID
    # @return [void]
    def leave_guild(guild_id)
      User.leave_guild(guild_id)
    end

    # Create a DM channel with a user
    # @param user_id [String, Snowflake] Target user ID
    # @return [Channel] DM channel
    def create_dm(user_id)
      data = @rest.post('/users/@me/channels', body: { recipient_id: user_id.to_s })
      Channel.new(data)
    end

    # Get OAuth2 connections for the current user
    # @return [Array<Hash>] User connections
    def current_user_connections
      User.get_connections
    end

    # Get application role connection metadata for the current user
    # @param application_id [String, Snowflake] Application ID
    # @return [Hash, nil] Role connection payload
    def application_role_connection(application_id)
      User.get_application_role_connection(application_id)
    end

    # Update application role connection metadata for the current user
    # @param application_id [String, Snowflake] Application ID
    # @param platform_name [String, nil] Platform name
    # @param platform_username [String, nil] Platform username
    # @param metadata [Hash] Metadata payload
    # @return [Hash, nil] Updated role connection payload
    def update_application_role_connection(application_id, platform_name: nil, platform_username: nil, metadata: {})
      User.update_application_role_connection(
        application_id,
        platform_name: platform_name,
        platform_username: platform_username,
        metadata: metadata
      )
    end

    # Get current bot application metadata
    # @return [Hash] Application payload
    def application_info
      @rest.get('/oauth2/applications/@me')
    end

    # Get current authorization information
    # @return [Hash] Authorization payload
    def authorization_info
      @rest.get('/oauth2/@me')
    end

    # Get gateway information
    # @return [Hash] Gateway payload
    def gateway
      @rest.get('/gateway')
    end

    # Get gateway bot information
    # @return [Hash] Gateway bot payload
    def gateway_bot
      @rest.get('/gateway/bot')
    end

    private

    def application_id_for_rest
      application_info['id']
    end

    def normalize_rest_params(options, *snowflake_keys)
      options.each_with_object({}) do |(key, value), params|
        next if value.nil?

        params[key] = snowflake_keys.include?(key) ? value.to_s : value
      end
    end

    def audit_log_headers(reason)
      reason ? { 'X-Audit-Log-Reason' => CGI.escape(reason) } : {}
    end

    def register_application_command(cmd, name:, guild_id: nil)
      cmd.instance_variable_set(:@application_id, me.id.to_s) rescue nil
      cmd.instance_variable_set(:@guild_id, guild_id.to_s) if guild_id

      key = guild_id ? "#{name}:#{guild_id}" : name
      @slash_commands[key] = cmd

      if cmd.application_id
        if guild_id
          cmd.create_guild(self, guild_id)
        else
          cmd.create_global(self)
        end
      end

      @logger.info('Registered application command', name: name, type: cmd.command_type, guild: guild_id || 'global')
      cmd
    end

    def configure_entity_apis(client)
      Message.api = client
      Interaction.api = client
      Interaction.supervisor = @supervisor
      User.api = client
      Guild.api = client
      Channel.api = client
    end

    def restart_gateway_state
      Array(@restart_state['shards']).each_with_object({}) do |shard, states|
        states[shard['shard_id']] = shard
      end
    end

    def install_signal_handlers
      return if defined?(@signal_handlers_installed) && @signal_handlers_installed

      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          @logger.info('Received shutdown signal', signal: signal)
          stop
        rescue StandardError => e
          @logger&.error('Failed during signal shutdown', signal: signal, error: e)
        end
      end

      @signal_handlers_installed = true
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
          @supervisor.execute(
            "command:#{key}",
            policy: cmd.execution_policy
          ) do
            cmd.handler.call(interaction)
          end
        rescue ExecutionSupervisor::TimeoutError => e
          @logger.error('Slash command timeout', command: cmd_name, error: e)
          interaction.respond(content: 'This command timed out and was stopped.', ephemeral: true) rescue nil
        rescue ExecutionSupervisor::ConcurrencyLimitError => e
          @logger.warn('Slash command concurrency limit', command: cmd_name, error: e)
          interaction.respond(content: 'This command is busy right now. Try again in a moment.', ephemeral: true) rescue nil
        rescue ExecutionSupervisor::CircuitOpenError => e
          @logger.warn('Slash command circuit open', command: cmd_name, error: e)
          interaction.respond(content: 'This command was temporarily disabled after repeated failures.', ephemeral: true) rescue nil
        rescue => e
          @logger.error('Slash command error', command: cmd_name, error: e)
          interaction.respond(content: "An error occurred while executing this command.", ephemeral: true) rescue nil
          @error_tracker.capture(e, command: cmd_name, user_id: interaction.user&.id)
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
