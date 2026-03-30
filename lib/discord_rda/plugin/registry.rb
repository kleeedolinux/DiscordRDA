# frozen_string_literal: true

module DiscordRDA
  # Plugin registry for managing loaded plugins.
  #
  class PluginRegistry
    # @return [Hash<Symbol, Plugin>] Registered plugins
    attr_reader :plugins

    # @return [Logger] Logger instance
    attr_reader :logger

    # Initialize registry
    # @param logger [Logger] Logger instance
    def initialize(logger: nil)
      @plugins = {}
      @logger = logger
      @mutex = Mutex.new
    end

    # Register a plugin
    # @param plugin [Plugin] Plugin to register
    # @param bot [Bot] Bot instance for setup
    # @return [Boolean] True if registered
    def register(plugin, bot)
      name = plugin.name.to_sym

      @mutex.synchronize do
        if @plugins.key?(name)
          @logger&.warn('Plugin already registered', name: name)
          return false
        end

        unless plugin.dependencies_met?(@plugins.keys)
          @logger&.error('Plugin dependencies not met', name: name, deps: plugin.dependencies)
          return false
        end

        @plugins[name] = plugin
        plugin.setup(bot)
        plugin.enable

        @logger&.info('Plugin registered', name: name, version: plugin.version)
        true
      end
    end

    # Unregister a plugin
    # @param name [Symbol] Plugin name
    # @return [Boolean] True if unregistered
    def unregister(name)
      name = name.to_sym

      @mutex.synchronize do
        plugin = @plugins.delete(name)
        return false unless plugin

        plugin.disable
        plugin.teardown

        @logger&.info('Plugin unregistered', name: name)
        true
      end
    end

    # Get a plugin by name
    # @param name [Symbol] Plugin name
    # @return [Plugin, nil] Plugin or nil
    def get(name)
      @plugins[name.to_sym]
    end

    # Check if plugin is registered
    # @param name [Symbol] Plugin name
    # @return [Boolean] True if registered
    def registered?(name)
      @plugins.key?(name.to_sym)
    end

    # Get all registered plugin names
    # @return [Array<Symbol>] Plugin names
    def names
      @plugins.keys
    end

    # Get all plugins
    # @return [Array<Plugin>] Plugins
    def all
      @plugins.values
    end

    # Get enabled plugins
    # @return [Array<Plugin>] Enabled plugins
    def enabled
      @plugins.values.select(&:enabled?)
    end

    # Clear all plugins
    # @return [void]
    def clear
      @mutex.synchronize do
        @plugins.each_value do |plugin|
          plugin.disable
          plugin.teardown
        end
        @plugins.clear
      end
    end

    # Get plugin count
    # @return [Integer] Number of plugins
    def count
      @plugins.size
    end

    # Get registry statistics
    # @return [Hash] Statistics
    def stats
      {
        total: @plugins.size,
        enabled: enabled.size,
        plugins: @plugins.transform_values(&:metadata)
      }
    end
  end
end
