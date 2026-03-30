# frozen_string_literal: true

require 'discord_rda'

# Scalable bot example demonstrating Discordeno-inspired features
# This example shows:
# - Scalable REST client with queue-based rate limiting
# - Invalid request bucket (prevents 1-hour bans)
# - Hot reload for development
# - Auto-resharding
# - Analytics plugin

token = ENV['DISCORD_TOKEN']

unless token
  puts 'Please set DISCORD_TOKEN environment variable'
  exit 1
end

# Create bot with scalable features
bot = DiscordRDA::Bot.new(
  token: token,
  shards: :auto,
  intents: [:guilds, :guild_messages, :message_content],
  log_level: :info,
  # Use configurable cache - by default caches NOTHING (Discordeno style)
  cache: :none
)

# Enable scalable REST client with queue-based rate limiting
# This prevents global rate limits and invalid request bans
bot.enable_scalable_rest

# Enable hot reload for instant code updates during development
bot.enable_hot_reload(watch_dir: 'lib') if ENV['DEVELOPMENT']

# Enable auto-resharding when guild count grows
# Automatically adds shards when exceeding 1000 guilds per shard
bot.enable_auto_reshard(max_guilds_per_shard: 1000)

# Register analytics plugin for beautiful metrics
analytics = DiscordRDA::AnalyticsPlugin.new(retention: 3600, logger: bot.logger)
bot.register_plugin(analytics)

# Event handlers
bot.on(:ready) do |event|
  puts "✅ Bot ready as #{event.user&.display_name}"
  puts "   Shards: #{bot.shard_manager.shard_count}"
  puts "   Guilds: #{event.guilds.length}"
end

bot.on(:message_create) do |event|
  next if event.author.bot?

  case event.content
  when '!status'
    # Show detailed status including scalable components
    status = bot.status
    invalid_status = bot.invalid_bucket_status

    info = [
      "**Bot Status**",
      "Running: #{status[:running]}",
      "Shards: #{status[:shards][:active_shards]}/#{status[:shards][:total_shards]}",
      "",
      "**Invalid Request Protection**",
      "Remaining: #{invalid_status&.dig(:remaining) || 'N/A'}",
      "Limit: #{invalid_status&.dig(:limit) || 'N/A'}",
      "",
      "**Cache**",
      "Strategy: #{status[:cache]&.dig(:strategy) || 'none'}",
      "Size: #{status[:cache]&.dig(:size) || 0}"
    ].join("\n")

    event.message.respond(content: info)

  when '!analytics'
    # Show analytics report
    report = analytics.pretty_report
    event.message.respond(content: "```\n#{report}\n```")

  when '!reshard '
    # Manual resharding command (owner only)
    if event.author.id.to_s == ENV['OWNER_ID']
      new_count = event.content.split[1].to_i
      if new_count > 0
        bot.reshard_to(new_count)
        event.message.respond(content: "Resharding to #{new_count} shards...")
      end
    end

  when '!reload'
    # Trigger hot reload (development only)
    if ENV['DEVELOPMENT']
      bot.hot_reload_manager.reload
      event.message.respond(content: "Hot reload triggered!")
    end
  end
end

# Periodic analytics logging
Async do
  loop do
    sleep(300) # Every 5 minutes
    puts analytics.pretty_report
  end
end

puts "🚀 Starting scalable bot..."
puts "   Features enabled:"
puts "   - Scalable REST client (queue-based rate limiting)"
puts "   - Invalid request protection"
puts "   - Auto-resharding"
puts "   - Hot reload (development)"
puts "   - Analytics"
bot.run
