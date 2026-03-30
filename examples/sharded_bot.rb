# frozen_string_literal: true

require 'discord_rda'

# Sharded bot example
# This demonstrates automatic sharding for large bots

token = ENV['DISCORD_TOKEN']

unless token
  puts 'Please set DISCORD_TOKEN environment variable'
  exit 1
end

# Create bot with automatic sharding
bot = DiscordRDA::Bot.new(
  token: token,
  shards: :auto,  # Automatically determine shard count
  intents: [:guilds, :guild_messages, :message_content],
  cache: :memory,
  log_level: :info
)

# Event handlers
bot.on(:ready) do |event|
  puts "✅ Shard #{event.shard_id} ready!"
  puts "   Guilds on this shard: #{event.guilds.length}"
end

bot.on(:message_create) do |event|
  next if event.author.bot?

  case event.content
  when '!shard'
    shard_info = bot.status[:shards]
    event.message.respond(
      content: "📊 Shard Info:\nTotal: #{shard_info[:total_shards]}\nActive: #{shard_info[:active_shards]}\nThis: Shard #{event.shard_id}"
    )

  when '!status'
    status = bot.status
    event.message.respond(
      content: "🤖 Bot Status:\nRunning: #{status[:running]}\nShards: #{status[:shards][:active_shards]}/#{status[:shards][:total_shards]}"
    )
  end
end

# Run the bot
puts "🚀 Starting sharded bot..."
bot.run
