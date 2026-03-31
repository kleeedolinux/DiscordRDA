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

    # Get messages from a channel with pagination (simplified)
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

    # === Message Reactions (Simplified) ===

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

    # Get reactions for a message (simplified - no pagination)
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @param emoji [String, Emoji] Emoji filter
    # @param limit [Integer] Max users to return (1-100, default 25)
    # @return [Array<User>] Users who reacted
    def get_reactions(channel_id, message_id, emoji, limit: 25)
      emoji_str = emoji.respond_to?(:id) ? "#{emoji.name}:#{emoji.id}" : emoji.to_s
      data = @rest.get("/channels/#{channel_id}/messages/#{message_id}/reactions/#{CGI.escape(emoji_str)}", params: { limit: limit })
      data.map { |u| User.new(u) }
    end

    # Remove all reactions from a message
    # @param channel_id [String, Snowflake] Channel ID
    # @param message_id [String, Snowflake] Message ID
    # @return [void]
    def remove_all_reactions(channel_id, message_id)
      @rest.delete("/channels/#{channel_id}/messages/#{message_id}/reactions")
    end

    # === Guild Members (Simplified) ===

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

    # List guild members (simplified - basic pagination)
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

    # Search guild members by query (simplified)
    # @param guild_id [String, Snowflake] Guild ID
    # @param query [String] Search query (username/nickname prefix)
    # @param limit [Integer] Max results (1-100, default 25)
    # @return [Array<Member>] Matching members
    def search_guild_members(guild_id, query, limit: 25)
      params = { query: query, limit: limit }
      data = @rest.get("/guilds/#{guild_id}/members/search", params: params)
      data.map { |m| Member.new(m.merge('guild_id' => guild_id.to_s)) }
    end

    # Modify a guild member (simplified)
    # @param guild_id [String, Snowflake] Guild ID
    # @param user_id [String, Snowflake] User ID
    # @param options [Hash] Options to modify (nick, roles, mute, deaf, channel_id)
    # @return [Member] Updated member
    def modify_guild_member(guild_id, user_id, **options)
      payload = options.slice(:nick, :roles, :mute, :deaf, :channel_id, :communication_disabled_until)
      data = @rest.patch("/guilds/#{guild_id}/members/#{user_id}", body: payload)
      Member.new(data.merge('guild_id' => guild_id.to_s))
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

    # === Guild Roles (Simplified) ===

    # Get guild roles
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Role>] Roles
    def guild_roles(guild_id)
      data = @rest.get("/guilds/#{guild_id}/roles")
      data.map { |r| Role.new(r.merge('guild_id' => guild_id.to_s)) }
    end

    # Create guild role (simplified)
    # @param guild_id [String, Snowflake] Guild ID
    # @param name [String] Role name
    # @param options [Hash] Optional settings (permissions, color, hoist, mentionable)
    # @return [Role] Created role
    def create_guild_role(guild_id, name:, **options)
      payload = { name: name }.merge(options.slice(:permissions, :color, :hoist, :mentionable, :icon, :unicode_emoji))
      data = @rest.post("/guilds/#{guild_id}/roles", body: payload)
      Role.new(data.merge('guild_id' => guild_id.to_s))
    end

    # Modify guild role
    # @param guild_id [String, Snowflake] Guild ID
    # @param role_id [String, Snowflake] Role ID
    # @param options [Hash] Settings to modify
    # @return [Role] Updated role
    def modify_guild_role(guild_id, role_id, **options)
      payload = options.slice(:name, :permissions, :color, :hoist, :mentionable, :icon, :unicode_emoji)
      data = @rest.patch("/guilds/#{guild_id}/roles/#{role_id}", body: payload)
      Role.new(data.merge('guild_id' => guild_id.to_s))
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

    # === Guild Bans (Simplified) ===

    # Get guild bans (simplified - no pagination)
    # @param guild_id [String, Snowflake] Guild ID
    # @param limit [Integer] Max bans (1-1000, default 100)
    # @return [Array<Hash>] Bans (user + reason data)
    def guild_bans(guild_id, limit: 100)
      data = @rest.get("/guilds/#{guild_id}/bans", params: { limit: limit })
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

    # === Webhooks (Simplified) ===

    # Create a webhook
    # @param channel_id [String, Snowflake] Channel ID
    # @param name [String] Webhook name
    # @param avatar [String] Base64-encoded avatar image (optional)
    # @return [Hash] Webhook data
    def create_webhook(channel_id, name:, avatar: nil)
      payload = { name: name }
      payload[:avatar] = avatar if avatar
      @rest.post("/channels/#{channel_id}/webhooks", body: payload)
    end

    # Get channel webhooks
    # @param channel_id [String, Snowflake] Channel ID
    # @return [Array<Hash>] Webhooks
    def channel_webhooks(channel_id)
      @rest.get("/channels/#{channel_id}/webhooks")
    end

    # Get guild webhooks
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Hash>] Webhooks
    def guild_webhooks(guild_id)
      @rest.get("/guilds/#{guild_id}/webhooks")
    end

    # Execute webhook (simplified)
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token
    # @param content [String] Message content
    # @param options [Hash] Options (username, avatar_url, embeds, etc.)
    # @return [void]
    def execute_webhook(webhook_id, token, content = nil, **options)
      payload = { content: content }.merge(options.slice(:username, :avatar_url, :embeds, :components, :allowed_mentions))
      @rest.post("/webhooks/#{webhook_id}/#{token}", body: payload)
    end

    # Delete a webhook
    # @param webhook_id [String, Snowflake] Webhook ID
    # @param token [String] Webhook token (optional, for webhook-owned deletes)
    # @return [void]
    def delete_webhook(webhook_id, token: nil)
      path = token ? "/webhooks/#{webhook_id}/#{token}" : "/webhooks/#{webhook_id}"
      @rest.delete(path)
    end

    # === Channel Management (Simplified) ===

    # Get guild channels
    # @param guild_id [String, Snowflake] Guild ID
    # @return [Array<Channel>] Channels
    def guild_channels(guild_id)
      data = @rest.get("/guilds/#{guild_id}/channels")
      data.map { |c| Channel.new(c) }
    end

    # Create guild channel (simplified)
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
