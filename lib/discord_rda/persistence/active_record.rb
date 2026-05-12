# frozen_string_literal: true

require 'fileutils'
require 'active_record'

module DiscordRDA
  class ActiveRecordSystem
    attr_reader :logger

    def initialize(logger: nil)
      @logger = logger
      @connected = false
    end

    def connect(database_url: nil, **config)
      require 'active_record'

      connection_config = config.dup
      connection_config[:url] = database_url if database_url
      connection_config[:url] ||= ENV['DATABASE_URL']
      raise ArgumentError, 'database_url or DATABASE_URL is required' unless connection_config[:url]

      ::ActiveRecord::Base.establish_connection(connection_config)
      ::DiscordRDA::Record.connection
      @connected = true
      logger&.info('ActiveRecord connected', adapter: ::ActiveRecord::Base.connection_db_config.adapter)
      self
    end

    def connected?
      @connected && ::ActiveRecord::Base.connected?
    rescue StandardError
      false
    end

    def disconnect
      return unless defined?(::ActiveRecord::Base)

      ::ActiveRecord::Base.connection_pool.disconnect!
      @connected = false
    end

    def migration_context(paths = default_migration_paths)
      require 'active_record'

      paths.each { |path| FileUtils.mkdir_p(path) }
      ::ActiveRecord::MigrationContext.new(paths, ::ActiveRecord::SchemaMigration)
    end

    def migrate(paths = default_migration_paths)
      migration_context(paths).migrate
    end

    def rollback(paths = default_migration_paths, steps: 1)
      migration_context(paths).rollback(steps)
    end

    def default_migration_paths
      ['db/migrate']
    end
  end

  class Record < ::ActiveRecord::Base
    self.abstract_class = true
  end

  module ActiveRecordMigration
    def self.[](version = 7.1)
      Class.new(::ActiveRecord::Migration[version])
    end
  end
end
