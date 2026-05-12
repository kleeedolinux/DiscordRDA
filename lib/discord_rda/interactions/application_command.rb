# frozen_string_literal: true

module DiscordRDA
  # Application Command (Slash Command) for Discord.
  # Supports Chat Input Commands (slash), User Commands, and Message Commands.
  #
  class ApplicationCommand < Entity
    # Command types
    TYPES = {
      chat_input: 1,      # Slash commands
      user: 2,            # User context menu commands
      message: 3          # Message context menu commands
    }.freeze

    # Option types
    OPTION_TYPES = {
      sub_command: 1,
      sub_command_group: 2,
      string: 3,
      integer: 4,
      boolean: 5,
      user: 6,
      channel: 7,
      role: 8,
      mentionable: 9,
      number: 10,
      attachment: 11
    }.freeze

    # Permission constants
    PERMISSIONS = {
      create_instant_invite: 1 << 0,
      kick_members: 1 << 1,
      ban_members: 1 << 2,
      administrator: 1 << 3,
      manage_channels: 1 << 4,
      manage_guild: 1 << 5,
      add_reactions: 1 << 6,
      view_audit_log: 1 << 7,
      priority_speaker: 1 << 8,
      stream: 1 << 9,
      view_channel: 1 << 10,
      send_messages: 1 << 11,
      send_tts_messages: 1 << 12,
      manage_messages: 1 << 13,
      embed_links: 1 << 14,
      attach_files: 1 << 15,
      read_message_history: 1 << 16,
      mention_everyone: 1 << 17,
      use_external_emojis: 1 << 18,
      view_guild_insights: 1 << 19,
      connect: 1 << 20,
      speak: 1 << 21,
      mute_members: 1 << 22,
      deafen_members: 1 << 23,
      move_members: 1 << 24,
      use_vad: 1 << 25,
      change_nickname: 1 << 26,
      manage_nicknames: 1 << 27,
      manage_roles: 1 << 28,
      manage_webhooks: 1 << 29,
      manage_emojis_and_stickers: 1 << 30,
      use_application_commands: 1 << 31,
      request_to_speak: 1 << 32,
      manage_events: 1 << 33,
      manage_threads: 1 << 34,
      create_public_threads: 1 << 35,
      create_private_threads: 1 << 36,
      use_external_stickers: 1 << 37,
      send_messages_in_threads: 1 << 38,
      use_embedded_activities: 1 << 39,
      moderate_members: 1 << 40
    }.freeze

    attribute :application_id, type: :snowflake
    attribute :name, type: :string
    attribute :name_localizations, type: :hash
    attribute :description, type: :string
    attribute :description_localizations, type: :hash
    attribute :options, type: :array
    attribute :default_member_permissions, type: :string
    attribute :dm_permission, type: :boolean, default: true
    attribute :default_permission, type: :boolean, default: true
    attribute :type, type: :integer, default: 1
    attribute :nsfw, type: :boolean, default: false
    attribute :version, type: :snowflake
    attribute :guild_id, type: :snowflake

    # Get command type as symbol
    # @return [Symbol] Command type
    def command_type
      TYPES.key(type) || :chat_input
    end

    # Check if this is a chat input (slash) command
    # @return [Boolean] True if slash command
    def chat_input?
      type == 1
    end

    # Check if this is a user context menu command
    # @return [Boolean] True if user command
    def user_command?
      type == 2
    end

    # Check if this is a message context menu command
    # @return [Boolean] True if message command
    def message_command?
      type == 3
    end

    # Get the handler block for this command
    # @return [Proc, nil] Handler block
    def handler
      @handler
    end

    def execution_policy
      @execution_policy ||= {}
    end

    # Set the handler block
    # @param block [Proc] Handler block
    def handler=(block)
      @handler = block
    end

    # Convert to API hash for creating/updating
    # @return [Hash] API payload
    def to_api_hash
      {
        name: name,
        name_localizations: name_localizations,
        description: description,
        description_localizations: description_localizations,
        options: options,
        default_member_permissions: default_member_permissions,
        dm_permission: dm_permission,
        type: type,
        nsfw: nsfw
      }.compact
    end

    # Create a global application command via REST API
    # @param bot [Bot] Bot instance
    # @return [ApplicationCommand] Created command
    def create_global(bot)
      data = bot.rest.post("/applications/#{application_id}/commands", body: to_api_hash)
      ApplicationCommand.new(data)
    end

    # Create a guild-specific application command via REST API
    # @param bot [Bot] Bot instance
    # @param guild_id [String, Snowflake] Guild ID
    # @return [ApplicationCommand] Created command
    def create_guild(bot, guild_id)
      gid = guild_id.to_s
      data = bot.rest.post("/applications/#{application_id}/guilds/#{gid}/commands", body: to_api_hash)
      ApplicationCommand.new(data)
    end

    # Edit this command
    # @param bot [Bot] Bot instance
    # @param changes [Hash] Changes to apply
    # @return [ApplicationCommand] Updated command
    def edit(bot, **changes)
      payload = to_api_hash.merge(changes)
      if guild_id
        data = bot.rest.patch("/applications/#{application_id}/guilds/#{guild_id}/commands/#{id}", body: payload)
      else
        data = bot.rest.patch("/applications/#{application_id}/commands/#{id}", body: payload)
      end
      ApplicationCommand.new(data)
    end

    # Delete this command
    # @param bot [Bot] Bot instance
    # @return [void]
    def delete(bot)
      if guild_id
        bot.rest.delete("/applications/#{application_id}/guilds/#{guild_id}/commands/#{id}")
      else
        bot.rest.delete("/applications/#{application_id}/commands/#{id}")
      end
    end

    # Get command permissions for this guild command
    # @param bot [Bot] Bot instance
    # @return [Hash] Command permissions
    def permissions(bot)
      return nil unless guild_id

      bot.rest.get("/applications/#{application_id}/guilds/#{guild_id}/commands/#{id}/permissions")
    end

    # Edit command permissions
    # @param bot [Bot] Bot instance
    # @param permissions [Array<Hash>] Permission overwrites
    # @return [Hash] Updated permissions
    def edit_permissions(bot, permissions)
      return nil unless guild_id

      payload = { permissions: permissions }
      bot.rest.put("/applications/#{application_id}/guilds/#{guild_id}/commands/#{id}/permissions", body: payload)
    end
  end

  # Builder for creating application commands with DSL
  class CommandBuilder
    def initialize(name, description = nil, type: 1)
      @name = name
      @description = description || ''
      @type = type
      @options = []
      @name_localizations = {}
      @description_localizations = {}
      @default_member_permissions = nil
      @dm_permission = true
      @nsfw = false
      @handler = nil
      @execution_policy = {}
    end

    # Set command type
    # @param type [Integer, Symbol] Discord command type
    # @return [self]
    def type(type)
      @type = type.is_a?(Symbol) ? ApplicationCommand::TYPES.fetch(type) : type
      self
    end

    # Set localized name
    # @param locale [String] Locale code (e.g., 'en-US', 'pt-BR')
    # @param name [String] Localized name
    def localized_name(locale, name)
      @name_localizations[locale] = name
      self
    end

    # Set localized description
    # @param locale [String] Locale code
    # @param description [String] Localized description
    def localized_description(locale, description)
      @description_localizations[locale] = description
      self
    end

    # Add a string option
    # @param name [String] Option name
    # @param description [String] Option description
    # @param required [Boolean] Whether required
    # @param choices [Array<Hash>] Predefined choices
    # @param min_length [Integer] Minimum length
    # @param max_length [Integer] Maximum length
    # @param autocomplete [Boolean] Enable autocomplete
    def string(name, description:, required: false, choices: nil, min_length: nil, max_length: nil, autocomplete: false)
      option = build_option(3, name, description, required: required)
      option[:choices] = choices if choices
      option[:min_length] = min_length if min_length
      option[:max_length] = max_length if max_length
      option[:autocomplete] = true if autocomplete
      @options << option
      self
    end

    # Add an integer option
    # @param name [String] Option name
    # @param description [String] Option description
    # @param required [Boolean] Whether required
    # @param choices [Array<Hash>] Predefined choices
    # @param min_value [Integer] Minimum value
    # @param max_value [Integer] Maximum value
    def integer(name, description:, required: false, choices: nil, min_value: nil, max_value: nil, autocomplete: false)
      option = build_option(4, name, description, required: required)
      option[:choices] = choices if choices
      option[:min_value] = min_value if min_value
      option[:max_value] = max_value if max_value
      option[:autocomplete] = true if autocomplete
      @options << option
      self
    end

    # Add a boolean option
    # @param name [String] Option name
    # @param description [String] Option description
    # @param required [Boolean] Whether required
    def boolean(name, description:, required: false)
      @options << build_option(5, name, description, required: required)
      self
    end

    # Add a user option
    # @param name [String] Option name
    # @param description [String] Option description
    # @param required [Boolean] Whether required
    def user(name, description:, required: false)
      @options << build_option(6, name, description, required: required)
      self
    end

    # Add a channel option
    # @param name [String] Option name
    # @param description [String] Option description
    # @param required [Boolean] Whether required
    # @param channel_types [Array<Integer>] Allowed channel types
    def channel(name, description:, required: false, channel_types: nil)
      option = build_option(7, name, description, required: required)
      option[:channel_types] = channel_types if channel_types
      @options << option
      self
    end

    # Add a role option
    # @param name [String] Option name
    # @param description [String] Option description
    # @param required [Boolean] Whether required
    def role(name, description:, required: false)
      @options << build_option(8, name, description, required: required)
      self
    end

    # Add a mentionable option (user or role)
    # @param name [String] Option name
    # @param description [String] Option description
    # @param required [Boolean] Whether required
    def mentionable(name, description:, required: false)
      @options << build_option(9, name, description, required: required)
      self
    end

    # Add a number (float) option
    # @param name [String] Option name
    # @param description [String] Option description
    # @param required [Boolean] Whether required
    # @param choices [Array<Hash>] Predefined choices
    # @param min_value [Float] Minimum value
    # @param max_value [Float] Maximum value
    def number(name, description:, required: false, choices: nil, min_value: nil, max_value: nil, autocomplete: false)
      option = build_option(10, name, description, required: required)
      option[:choices] = choices if choices
      option[:min_value] = min_value if min_value
      option[:max_value] = max_value if max_value
      option[:autocomplete] = true if autocomplete
      @options << option
      self
    end

    # Add an attachment option
    # @param name [String] Option name
    # @param description [String] Option description
    # @param required [Boolean] Whether required
    def attachment(name, description:, required: false)
      @options << build_option(11, name, description, required: required)
      self
    end

    # Add a subcommand
    # @param name [String] Subcommand name
    # @param description [String] Subcommand description
    # @yield [CommandBuilder] Block for building subcommand options
    def subcommand(name, description, &block)
      builder = CommandBuilder.new(name, description, type: 1)
      block.call(builder) if block
      @options << builder.to_h
      self
    end

    # Add a subcommand group
    # @param name [String] Group name
    # @param description [String] Group description
    # @yield [CommandBuilder] Block for building subcommands in this group
    def group(name, description, &block)
      builder = CommandBuilder.new(name, description, type: 2)
      block.call(builder) if block
      @options << builder.to_h
      self
    end

    # Set default member permissions
    # @param permissions [Integer, Array<Symbol>] Permission bits or symbols
    def default_permissions(permissions)
      @default_member_permissions = if permissions.is_a?(Array)
        permissions.map { |p| ApplicationCommand::PERMISSIONS[p] || p }.reduce(:|).to_s
      else
        permissions.to_s
      end
      self
    end

    # Set DM permission
    # @param allowed [Boolean] Whether command works in DMs
    def dm_allowed(allowed = true)
      @dm_permission = allowed
      self
    end

    # Set NSFW flag
    # @param nsfw [Boolean] Whether command is age-restricted
    def nsfw(nsfw = true)
      @nsfw = nsfw
      self
    end

    # Define the handler block
    # @yield [Interaction] Interaction handler
    def handler(&block)
      @handler = block
      self
    end

    def timeout(seconds)
      @execution_policy[:timeout_seconds] = seconds.to_f
      self
    end

    def max_concurrency(value)
      @execution_policy[:max_concurrency] = value.to_i
      self
    end

    def circuit_breaker(failures:, cooldown:)
      @execution_policy[:failure_threshold] = failures.to_i
      @execution_policy[:cooldown_seconds] = cooldown.to_f
      self
    end

    def execution_policy(**policy)
      @execution_policy.merge!(policy)
      self
    end

    # Convert to hash for API
    # @return [Hash] Command hash
    def to_h
      {
        name: @name,
        name_localizations: @name_localizations.empty? ? nil : @name_localizations,
        description: @description,
        description_localizations: @description_localizations.empty? ? nil : @description_localizations,
        options: @options.empty? ? nil : @options,
        default_member_permissions: @default_member_permissions,
        dm_permission: @dm_permission,
        type: @type,
        nsfw: @nsfw
      }.compact
    end

    # Build and return ApplicationCommand
    # @return [ApplicationCommand] Command instance
    def build
      cmd = ApplicationCommand.new(to_h)
      cmd.handler = @handler
      cmd.instance_variable_set(:@execution_policy, @execution_policy.dup)
      cmd
    end

    private

    def build_option(type, name, description, required: false)
      {
        type: type,
        name: name,
        name_localizations: {},
        description: description,
        description_localizations: {},
        required: required
      }
    end
  end
end
