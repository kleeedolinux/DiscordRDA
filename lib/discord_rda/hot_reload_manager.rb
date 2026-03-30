# frozen_string_literal: true

module DiscordRDA
  # Hot reload manager for instant bot restarts without losing state.
  # Allows updating code without downtime.
  #
  # Uses the listen gem for file system event-based watching on supported platforms,
  # with graceful fallback to polling on unsupported platforms.
  #
  class HotReloadManager
    # @return [Bot] Bot instance
    attr_reader :bot

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [String] Watch directory
    attr_reader :watch_dir

    # @return [Array<String>] File patterns to watch
    attr_reader :patterns

    # @return [Boolean] Whether hot reload is enabled
    attr_reader :enabled

    # @return [Hash] State to preserve across reloads
    attr_reader :preserved_state

    # @return [Boolean] Whether using native file system events
    attr_reader :native_watching

    # Initialize hot reload manager
    # @param bot [Bot] Bot instance
    # @param logger [Logger] Logger instance
    # @param watch_dir [String] Directory to watch
    # @param patterns [Array<String>] File patterns to watch
    def initialize(bot, logger, watch_dir: 'lib', patterns: ['*.rb'])
      @bot = bot
      @logger = logger
      @watch_dir = watch_dir
      @patterns = patterns
      @enabled = false
      @preserved_state = {}
      @watcher = nil
      @native_watching = false
      @file_mtimes = {}
      @debounce_timer = nil
    end

    # Enable hot reload
    # @return [void]
    def enable
      return if @enabled

      @enabled = true
      start_watching
      @logger.info('Hot reload enabled', watch_dir: @watch_dir, native: @native_watching)
    end

    # Disable hot reload
    # @return [void]
    def disable
      return unless @enabled

      @enabled = false
      stop_watching
      @logger.info('Hot reload disabled')
    end

    # Preserve state before reload
    # @param key [Symbol] State key
    # @param value [Object] State value
    # @return [void]
    def preserve_state(key, value)
      @preserved_state[key] = value
    end

    # Get preserved state
    # @param key [Symbol] State key
    # @return [Object] State value
    def get_preserved_state(key)
      @preserved_state[key]
    end

    # Clear preserved state
    # @return [void]
    def clear_state
      @preserved_state.clear
    end

    # Trigger manual reload
    # @return [void]
    def reload
      @logger.info('Hot reload triggered')

      # Step 1: Preserve critical state
      preserve_bot_state

      # Step 2: Disconnect old event handlers
      @bot.event_bus.handlers.clear

      # Step 3: Reload files
      reload_files

      # Step 4: Restore state
      restore_bot_state

      # Step 5: Re-register handlers
      reinitialize_handlers

      @logger.info('Hot reload complete')
    end

    # Get status
    # @return [Hash] Status information
    def status
      {
        enabled: @enabled,
        watch_dir: @watch_dir,
        patterns: @patterns,
        preserved_keys: @preserved_state.keys,
        native_watching: @native_watching
      }
    end

    private

    def start_watching
      # Try to use listen gem for native file system events
      begin
        require 'listen'
        start_listen_watcher
        @native_watching = true
      rescue LoadError
        @logger.warn('Listen gem not available, falling back to polling')
        start_polling_watcher
        @native_watching = false
      end
    end

    def start_listen_watcher
      # Use listen gem for efficient file system event watching
      @watcher = Listen.to(@watch_dir, only: @patterns) do |modified, added, removed|
        files = modified + added + removed
        next if files.empty?

        @logger.debug('Files changed', files: files)
        debounce_reload
      end

      @watcher.start
    end

    def start_polling_watcher
      # Fallback polling mechanism for unsupported platforms
      scan_files

      @watcher = Async do
        loop do
          sleep(2)
          check_for_changes if @enabled
        end
      end
    end

    def stop_watching
      if @native_watching && @watcher.is_a?(Listen::Listener)
        @watcher.stop
      else
        @watcher&.stop
      end
      @watcher = nil
      @debounce_timer&.stop
      @debounce_timer = nil
    end

    def debounce_reload
      # Cancel existing timer if any
      @debounce_timer&.stop

      # Set new timer - reload after 500ms of no changes
      @debounce_timer = Async do
        sleep(0.5)
        reload if @enabled
      end
    end

    def scan_files
      # Scan all watched files and record their modification times
      @file_mtimes.clear
      files_to_watch.each do |file|
        @file_mtimes[file] = File.mtime(file).to_f
      end
    end

    def check_for_changes
      # Check if any watched files have been modified
      changed_files = []

      files_to_watch.each do |file|
        current_mtime = File.mtime(file).to_f rescue next
        previous_mtime = @file_mtimes[file]

        if previous_mtime.nil? || current_mtime > previous_mtime
          changed_files << file
          @file_mtimes[file] = current_mtime
        end
      end

      # Handle deleted files
      @file_mtimes.each_key do |file|
        unless File.exist?(file)
          changed_files << file
          @file_mtimes.delete(file)
        end
      end

      return if changed_files.empty?

      @logger.debug('Files changed (polling)', files: changed_files)
      debounce_reload
    end

    def files_to_watch
      # Get list of files matching watched patterns
      @patterns.flat_map do |pattern|
        Dir.glob(File.join(@watch_dir, '**', pattern))
      end.uniq
    end

    def preserve_bot_state
      @logger.debug('Preserving bot state')

      # Preserve:
      # - Session IDs for resuming
      # - Sequence numbers
      # - Rate limit information
      # - Guild counts
      # - Any user-defined state

      @bot.shard_manager.shards.each do |shard|
        preserve_state(:"shard_#{shard_id(shard)}_session", shard.session_id)
        preserve_state(:"shard_#{shard_id(shard)}_sequence", shard.sequence)
      end

      preserve_state(:total_guilds, @bot.shard_manager.total_guilds)
    end

    def shard_id(shard)
      shard.instance_variable_get(:@shard_id)
    end

    def reload_files
      @logger.debug('Reloading files')

      # Clear load paths and reload
      files_to_reload = Dir.glob(File.join(@watch_dir, '**', @patterns))

      files_to_reload.each do |file|
        # Remove from loaded features
        $LOADED_FEATURES.delete_if { |f| f.include?(file) }

        # Reload
        begin
          load file
          @logger.debug('Reloaded file', file: file)
        rescue => e
          @logger.error('Failed to reload file', file: file, error: e)
        end
      end
    end

    def restore_bot_state
      @logger.debug('Restoring bot state')

      # Restore session IDs and sequences for resume
      @bot.shard_manager.shards.each do |shard|
        id = shard_id(shard)

        session = get_preserved_state(:"shard_#{id}_session")
        sequence = get_preserved_state(:"shard_#{id}_sequence")

        if session && sequence
          shard.instance_variable_set(:@session_id, session)
          shard.instance_variable_set(:@sequence, sequence)
        end
      end

      guilds = get_preserved_state(:total_guilds)
      @bot.shard_manager.update_guild_count(guilds) if guilds
    end

    def reinitialize_handlers
      @logger.debug('Reinitializing handlers')

      # Re-run the bot's setup event handlers
      # This would call any user-defined setup blocks again
      @bot.plugins.all.each do |plugin|
        plugin.setup(@bot) if plugin.respond_to?(:setup)
      end
    end
  end
end
