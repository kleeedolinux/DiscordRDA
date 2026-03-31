# frozen_string_literal: true

module DiscordRDA
  # Base class for plugins.
  # Plugins provide modular functionality for bots.
  #
  class Plugin
    # @return [String] Plugin name
    attr_reader :name

    # @return [String] Plugin version
    attr_reader :version

    # @return [String] Plugin description
    attr_reader :description

    # @return [Array<Symbol>] Plugin dependencies
    attr_reader :dependencies

    # Initialize plugin
    # @param name [String] Plugin name
    # @param version [String] Plugin version
    # @param description [String] Plugin description
    # @param dependencies [Array<Symbol>] Plugin dependencies
    def initialize(name: nil, version: '1.0.0', description: '', dependencies: [])
      @name = name || self.class.name
      @version = version
      @description = description
      @dependencies = dependencies
      @enabled = false
    end

    # Called when plugin is loaded
    # @param bot [Bot] Bot instance
    # @return [void]
    def setup(bot)
      # Override in subclass
    end

    # Called when bot is ready
    # @param bot [Bot] Bot instance
    # @return [void]
    def ready(bot)
      # Override in subclass
    end

    # Called when plugin is unloaded
    # @return [void]
    def teardown
      # Override in subclass
    end

    # Enable the plugin
    # @return [void]
    def enable
      @enabled = true
    end

    # Disable the plugin
    # @return [void]
    def disable
      @enabled = false
    end

    # Check if plugin is enabled
    # @return [Boolean] True if enabled
    def enabled?
      @enabled
    end

    # Check if plugin has required dependencies
    # @param loaded_plugins [Array<Symbol>] Loaded plugin names
    # @return [Boolean] True if all dependencies met
    def dependencies_met?(loaded_plugins)
      @dependencies.all? { |dep| loaded_plugins.include?(dep) }
    end

    # Register middleware with the bot
    # @param bot [Bot] Bot instance
    # @return [void]
    def register_middleware(bot)
      self.class.middlewares.each do |mw|
        bot.use(mw)
      end
    end

    # Plugin metadata
    # @return [Hash] Metadata
    def metadata
      {
        name: @name,
        version: @version,
        description: @description,
        dependencies: @dependencies,
        enabled: @enabled,
        commands: self.class.commands.length,
        handlers: self.class.handlers.length,
        middlewares: self.class.middlewares.length
      }
    end

    # DSL for defining plugin components
    class << self
      # Define a command
      # @param name [String] Command name
      # @param description [String] Command description
      # @param options [Array<Hash>] Command options
      # @yield Command handler block
      def command(name, description: '', options: [], &block)
        @commands ||= []
        @commands << { name: name, description: description, options: options, handler: block }
      end

      # Define an event handler
      # @param event [String, Symbol] Event type
      # @yield Event handler block
      def on(event, &block)
        @handlers ||= []
        @handlers << { event: event, handler: block }
      end

      # Define middleware
      # @yield Middleware block
      def middleware(&block)
        @middlewares ||= []
        @middlewares << block
      end

      # Define a before_setup hook
      # @yield Block to run before setup
      def before_setup(&block)
        @before_setup = block
      end

      # Define an after_setup hook
      # @yield Block to run after setup
      def after_setup(&block)
        @after_setup = block
      end

      # Get defined commands
      # @return [Array<Hash>] Commands
      def commands
        @commands || []
      end

      # Get defined handlers
      # @return [Array<Hash>] Handlers
      def handlers
        @handlers || []
      end

      # Get defined middlewares
      # @return [Array<Proc>] Middlewares
      def middlewares
        @middlewares || []
      end

      # Get before_setup hook
      # @return [Proc, nil] Hook
      def before_setup_hook
        @before_setup
      end

      # Get after_setup hook
      # @return [Proc, nil] Hook
      def after_setup_hook
        @after_setup
      end
    end

    # Register commands with the bot
    # @param bot [Bot] Bot instance
    # @return [void]
    def register_commands(bot)
      self.class.commands.each do |cmd|
        bot.register_command(cmd[:name], cmd[:description], cmd[:options], &cmd[:handler])
      end
    end

    # Register event handlers with the bot
    # @param bot [Bot] Bot instance
    # @return [void]
    def register_handlers(bot)
      self.class.handlers.each do |handler|
        bot.on(handler[:event], &handler[:handler])
      end
    end
  end
end
