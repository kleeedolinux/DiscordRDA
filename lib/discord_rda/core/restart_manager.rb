# frozen_string_literal: true

require 'json'
require 'rbconfig'
require 'securerandom'
require 'tmpdir'

module DiscordRDA
  class RestartManager
    STATE_ENV = 'DISCORD_RDA_RESTART_STATE_PATH'

    attr_reader :logger

    def initialize(logger:)
      @logger = logger
      @bot = nil
    end

    def attach(bot)
      @bot = bot
    end

    def consume_boot_state
      path = ENV.delete(STATE_ENV)
      return {} unless path && File.exist?(path)

      data = JSON.parse(File.read(path))
      File.delete(path)
      logger&.info('Loaded restart state', shards: (data['shards'] || []).length)
      data
    rescue StandardError => e
      logger&.error('Failed to load restart state', error: e)
      {}
    end

    def restart!(command: nil, env: {})
      raise 'Restart manager is not attached to a bot instance' unless @bot

      state_path = write_restart_state
      restart_command = command || default_command

      logger&.info('Performing instant restart', command: restart_command)

      exec(
        {
          STATE_ENV => state_path,
          'DISCORD_RDA_RESTARTED_AT' => Time.now.utc.iso8601
        }.merge(env),
        RbConfig.ruby,
        *restart_command
      )
    end

    private

    def write_restart_state
      path = File.join(Dir.tmpdir, "discord_rda_restart_#{Process.pid}_#{SecureRandom.hex(6)}.json")
      File.write(path, JSON.pretty_generate(snapshot_state))
      path
    end

    def snapshot_state
      {
        pid: Process.pid,
        written_at: Time.now.utc.iso8601,
        total_guilds: @bot.shard_manager.total_guilds,
        shards: @bot.shard_manager.shards.map do |shard|
          {
            shard_id: shard.instance_variable_get(:@shard_id),
            shard_count: shard.instance_variable_get(:@shard_count),
            session_id: shard.session_id,
            sequence: shard.sequence,
            resume_gateway_url: shard.resume_gateway_url
          }
        end
      }
    end

    def default_command
      [$PROGRAM_NAME, *ARGV]
    end
  end
end
