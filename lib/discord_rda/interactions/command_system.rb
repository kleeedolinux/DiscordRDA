# frozen_string_literal: true

module DiscordRDA
  # Full command system for Discord slash commands
  # Provides command registration, subcommands, permissions, cooldowns, and middleware
  #
  class CommandSystem
    # @return [Hash] Registered commands by name
    attr_reader :commands

    # @return [Array] Global middleware chain
    attr_reader :middleware

    # @return [Logger] Logger instance
    attr_reader :logger

    def initialize(logger: nil)
      @commands = {}
      @middleware = []
      @logger = logger
      @cooldowns = {}
    end

    # Register a command
    # @param name [String] Command name
    # @param description [String] Command description
    # @param options [Array] Command options
    # @param subcommands [Hash] Subcommand handlers
    # @param subcommand_groups [Hash] Subcommand group handlers
    # @param permissions [Array] Required permissions
    # @param cooldown [Hash] Cooldown configuration { duration: seconds, scope: :user/:guild/:channel }
    # @param middleware [Array] Per-command middleware
    # @param block [Proc] Command handler
    # @return [Command] Registered command
    def register(name, description:, options: [], subcommands: {}, subcommand_groups: {},
                 permissions: [], cooldown: nil, middleware: [], &block)
      command = Command.new(
        name: name,
        description: description,
        options: options,
        subcommands: subcommands,
        subcommand_groups: subcommand_groups,
        permissions: permissions,
        cooldown: cooldown,
        middleware: middleware,
        handler: block,
        system: self
      )

      @commands[name.to_s] = command
      @logger&.info('Command registered', name: name)
      command
    end

    # Register a subcommand
    # @param parent [String] Parent command name
    # @param name [String] Subcommand name
    # @param description [String] Description
    # @param options [Array] Options
    # @param permissions [Array] Required permissions
    # @param block [Proc] Handler
    # @return [Subcommand] Registered subcommand
    def register_subcommand(parent, name, description:, options: [], permissions: [], &block)
      parent_cmd = @commands[parent.to_s]
      raise "Parent command '#{parent}' not found" unless parent_cmd

      subcommand = Subcommand.new(
        name: name,
        description: description,
        options: options,
        permissions: permissions,
        handler: block,
        parent: parent_cmd
      )

      parent_cmd.subcommands[name.to_s] = subcommand
      @logger&.info('Subcommand registered', parent: parent, name: name)
      subcommand
    end

    # Register a subcommand group
    # @param parent [String] Parent command name
    # @param name [String] Group name
    # @param description [String] Description
    # @param subcommands [Hash] Subcommands in this group
    # @return [SubcommandGroup] Registered group
    def register_subcommand_group(parent, name, description:, subcommands: {})
      parent_cmd = @commands[parent.to_s]
      raise "Parent command '#{parent}' not found" unless parent_cmd

      group = SubcommandGroup.new(
        name: name,
        description: description,
        subcommands: subcommands,
        parent: parent_cmd
      )

      parent_cmd.subcommand_groups[name.to_s] = group
      @logger&.info('Subcommand group registered', parent: parent, name: name)
      group
    end

    # Add global middleware
    # @param middleware [Middleware, Proc] Middleware to add
    # @return [self]
    def use(middleware)
      @middleware << middleware
      self
    end

    # Handle an interaction
    # @param interaction [Interaction] The interaction to handle
    # @return [Object] Handler result
    def handle(interaction)
      return nil unless interaction.command?

      command_data = interaction.command_data
      return nil unless command_data

      command_name = command_data['name']
      command = @commands[command_name.to_s]

      return nil unless command

      context = CommandContext.new(interaction, self)

      # Run global middleware
      @middleware.each do |mw|
        result = mw.call(context)
        return result if result == :halt
      end

      # Run command
      command.execute(context)
    rescue => e
      @logger&.error('Command execution failed', error: e, command: command_name)
      raise
    end

    # Check if a command is on cooldown
    # @param command_name [String] Command name
    # @param user_id [String] User ID
    # @param guild_id [String] Guild ID (optional)
    # @return [Float, nil] Seconds remaining on cooldown, or nil if not on cooldown
    def cooldown_remaining(command_name, user_id:, guild_id: nil)
      key = cooldown_key(command_name, user_id, guild_id)
      expires_at = @cooldowns[key]
      return nil unless expires_at

      remaining = expires_at - Time.now.to_f
      remaining > 0 ? remaining : nil
    end

    # Apply cooldown for a command
    # @param command_name [String] Command name
    # @param duration [Integer] Cooldown duration in seconds
    # @param user_id [String] User ID
    # @param guild_id [String] Guild ID (optional)
    # @param scope [Symbol] Cooldown scope (:user, :guild, :channel)
    def apply_cooldown(command_name, duration, user_id:, guild_id: nil, scope: :user)
      key = cooldown_key(command_name, user_id, guild_id, scope)
      @cooldowns[key] = Time.now.to_f + duration
    end

    # Clear all cooldowns
    def clear_cooldowns
      @cooldowns.clear
    end

    # Get all commands as Discord application command JSON
    # @return [Array<Hash>] Commands as Discord API format
    def to_discord_commands
      @commands.values.map(&:to_discord_format)
    end

    private

    def cooldown_key(command_name, user_id, guild_id, scope = :user)
      case scope
      when :user
        "#{command_name}:user:#{user_id}"
      when :guild
        "#{command_name}:guild:#{guild_id || 'dm'}"
      when :channel
        "#{command_name}:channel:#{guild_id || user_id}"
      else
        "#{command_name}:user:#{user_id}"
      end
    end
  end

  # Represents a registered command
  class Command
    # @return [String] Command name
    attr_reader :name

    # @return [String] Command description
    attr_reader :description

    # @return [Array] Command options
    attr_reader :options

    # @return [Hash] Subcommands by name
    attr_reader :subcommands

    # @return [Hash] Subcommand groups by name
    attr_reader :subcommand_groups

    # @return [Array] Required permissions
    attr_reader :permissions

    # @return [Hash] Cooldown configuration
    attr_reader :cooldown

    # @return [Array] Per-command middleware
    attr_reader :middleware

    # @return [Proc] Command handler
    attr_reader :handler

    # @return [CommandSystem] Parent command system
    attr_reader :system

    def initialize(name:, description:, options: [], subcommands: {}, subcommand_groups: {},
                   permissions: [], cooldown: nil, middleware: [], handler:, system:)
      @name = name.to_s
      @description = description
      @options = options
      @subcommands = subcommands
      @subcommand_groups = subcommand_groups
      @permissions = permissions
      @cooldown = cooldown
      @middleware = middleware
      @handler = handler
      @system = system
    end

    # Execute the command
    # @param context [CommandContext] Command context
    # @return [Object] Handler result
    def execute(context)
      # Check permissions
      unless check_permissions(context)
        return context.respond(content: "You don't have permission to use this command.", ephemeral: true)
      end

      # Check cooldown
      if @cooldown
        remaining = system.cooldown_remaining(name, user_id: context.user.id.to_s, guild_id: context.guild_id)
        if remaining
          return context.respond(
            content: "This command is on cooldown. Try again in #{remaining.round} seconds.",
            ephemeral: true
          )
        end

        system.apply_cooldown(
          name,
          @cooldown[:duration] || 3,
          user_id: context.user.id.to_s,
          guild_id: context.guild_id,
          scope: @cooldown[:scope] || :user
        )
      end

      # Run command middleware
      @middleware.each do |mw|
        result = mw.call(context)
        return result if result == :halt
      end

      # Handle subcommands or groups
      if context.subcommand_group
        group = subcommand_groups[context.subcommand_group.to_s]
        return handler.call(context) unless group

        subcommand = group.subcommands[context.subcommand.to_s]
        return subcommand&.execute(context) || handler.call(context)
      elsif context.subcommand
        subcommand = subcommands[context.subcommand.to_s]
        return subcommand&.execute(context) || handler.call(context)
      end

      # Execute main handler
      handler.call(context)
    end

    # Check if user has required permissions
    # @param context [CommandContext] Command context
    # @return [Boolean] True if has permissions
    def check_permissions(context)
      return true if permissions.empty?
      return true unless context.member

      permissions.all? { |perm| context.member.permissions&.send("#{perm}?") }
    end

    # Convert to Discord API format
    # @return [Hash] Discord command JSON
    def to_discord_format
      cmd = {
        name: name,
        description: description,
        options: options
      }

      # Add subcommands and groups as options
      subcommand_groups.each do |name, group|
        cmd[:options] << {
          type: 2, # SUB_COMMAND_GROUP
          name: name,
          description: group.description,
          options: group.subcommands.values.map(&:to_option_format)
        }
      end

      subcommands.each do |name, sub|
        cmd[:options] << sub.to_option_format
      end

      cmd
    end
  end

  # Represents a subcommand
  class Subcommand
    attr_reader :name, :description, :options, :permissions, :handler, :parent

    def initialize(name:, description:, options:, permissions:, handler:, parent:)
      @name = name.to_s
      @description = description
      @options = options
      @permissions = permissions
      @handler = handler
      @parent = parent
    end

    # Execute subcommand
    # @param context [CommandContext] Command context
    def execute(context)
      # Check permissions
      unless check_permissions(context)
        return context.respond(content: "You don't have permission to use this subcommand.", ephemeral: true)
      end

      handler.call(context)
    end

    def check_permissions(context)
      return true if permissions.empty?
      return true unless context.member

      permissions.all? { |perm| context.member.permissions&.send("#{perm}?") }
    end

    def to_option_format
      {
        type: 1, # SUB_COMMAND
        name: name,
        description: description,
        options: options
      }
    end
  end

  # Represents a subcommand group
  class SubcommandGroup
    attr_reader :name, :description, :subcommands, :parent

    def initialize(name:, description:, subcommands:, parent:)
      @name = name.to_s
      @description = description
      @subcommands = subcommands
      @parent = parent
    end
  end

  # Context for command execution
  class CommandContext
    # @return [Interaction] The interaction
    attr_reader :interaction

    # @return [CommandSystem] The command system
    attr_reader :system

    # @return [User] The user who invoked the command
    attr_reader :user

    # @return [Member, nil] The member who invoked the command
    attr_reader :member

    # @return [Guild, nil] The guild where the command was invoked
    attr_reader :guild

    # @return [Channel] The channel where the command was invoked
    attr_reader :channel

    def initialize(interaction, system)
      @interaction = interaction
      @system = system
      @user = interaction.user
      @member = interaction.member
      @guild = nil # Would need to fetch from cache
      @channel = nil # Would need to fetch from cache
    end

    # Get command options
    # @return [Hash] Option name to value mapping
    def options
      interaction.options || {}
    end

    # Get a specific option value
    # @param name [String] Option name
    # @return [Object] Option value
    def option(name)
      options[name.to_s]
    end

    # Get subcommand name
    # @return [String, nil] Subcommand name
    def subcommand
      data = interaction.command_data
      return nil unless data && data['options']

      sub = data['options'].find { |opt| opt['type'] == 1 }
      sub&.dig('name')
    end

    # Get subcommand group name
    # @return [String, nil] Group name
    def subcommand_group
      data = interaction.command_data
      return nil unless data && data['options']

      group = data['options'].find { |opt| opt['type'] == 2 }
      group&.dig('name')
    end

    # Get guild ID
    # @return [String, nil] Guild ID
    def guild_id
      interaction.guild_id&.to_s
    end

    # Get channel ID
    # @return [String] Channel ID
    def channel_id
      interaction.channel_id&.to_s
    end

    # Respond to the interaction
    # @param content [String] Message content
    # @param options [Hash] Response options
    def respond(content = nil, **options, &block)
      interaction.respond(content, **options, &block)
    end

    # Defer the response
    # @param ephemeral [Boolean] Whether to make response ephemeral
    def defer(ephemeral: false)
      interaction.defer(ephemeral: ephemeral)
    end

    # Send a followup message
    # @param content [String] Message content
    # @param options [Hash] Message options
    def followup(content = nil, **options, &block)
      interaction.followup(content, **options, &block)
    end

    # Check if this is a guild context
    # @return [Boolean] True if in guild
    def guild?
      !guild_id.nil?
    end

    # Check if this is a DM context
    # @return [Boolean] True if in DM
    def dm?
      guild_id.nil?
    end
  end
end
