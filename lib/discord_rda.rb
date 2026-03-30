# frozen_string_literal: true

# DiscordRDA - Modern, scalable Ruby library for Discord bots
# Licensed under the Júlia Klee License
# Created by Júlia Klee

require_relative 'discord_rda/version'
require_relative 'discord_rda/core/async_runtime'
require_relative 'discord_rda/core/configuration'
require_relative 'discord_rda/core/logger'
require_relative 'discord_rda/core/snowflake'
require_relative 'discord_rda/entity/base'
require_relative 'discord_rda/entity/factory'
require_relative 'discord_rda/entity/user'
require_relative 'discord_rda/entity/guild'
require_relative 'discord_rda/entity/channel'
require_relative 'discord_rda/entity/message'
require_relative 'discord_rda/entity/message_builder'
require_relative 'discord_rda/entity/role'
require_relative 'discord_rda/entity/member'
require_relative 'discord_rda/entity/value_objects'
require_relative 'discord_rda/entity/color'
require_relative 'discord_rda/entity/emoji'
require_relative 'discord_rda/entity/attachment'
require_relative 'discord_rda/entity/embed'
require_relative 'discord_rda/entity/support'
require_relative 'discord_rda/connection/rate_limiter'
require_relative 'discord_rda/connection/invalid_bucket'
require_relative 'discord_rda/connection/request_queue'
require_relative 'discord_rda/connection/scalable_rest_client'
require_relative 'discord_rda/connection/rest_proxy'
require_relative 'discord_rda/connection/reshard_manager'
require_relative 'discord_rda/connection/gateway_client'
require_relative 'discord_rda/connection/rest_client'
require_relative 'discord_rda/connection/shard_manager'
require_relative 'discord_rda/event/bus'
require_relative 'discord_rda/event/base'
require_relative 'discord_rda/interactions/application_command'
require_relative 'discord_rda/interactions/interaction'
require_relative 'discord_rda/interactions/components'
require_relative 'discord_rda/cache/store'
require_relative 'discord_rda/cache/memory_store'
require_relative 'discord_rda/cache/redis_store'
require_relative 'discord_rda/cache/entity_cache'
require_relative 'discord_rda/cache/configurable_cache'
require_relative 'discord_rda/plugin/base'
require_relative 'discord_rda/plugin/registry'
require_relative 'discord_rda/plugin/analytics_plugin'
require_relative 'discord_rda/hot_reload_manager'
require_relative 'discord_rda/bot'

module DiscordRDA
  # Module-level shortcuts
  class << self
    # Create a new bot
    # @param token [String] Bot token
    # @param options [Hash] Configuration options
    # @return [Bot] New bot instance
    def bot(token:, **options)
      Bot.new(token: token, **options)
    end

    # Shortcut for Bot.new
    alias new bot
  end
end
