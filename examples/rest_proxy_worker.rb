# frozen_string_literal: true

require 'discord_rda'

# REST Proxy Worker example
# This demonstrates horizontal scaling with a central REST proxy
# Multiple bot workers can share a single REST connection pool

token = ENV['DISCORD_TOKEN']
proxy_url = ENV['REST_PROXY_URL'] || 'http://localhost:8000'
proxy_auth = ENV['REST_PROXY_AUTH'] || 'secret'

unless token
  puts 'Please set DISCORD_TOKEN environment variable'
  exit 1
end

# Create bot with REST proxy for horizontal scaling
bot = DiscordRDA::Bot.new(
  token: token,
  shards: [[0, 4], [1, 4], [2, 4], [3, 4]], # 4 shards, manual for workers
  intents: [:guilds, :guild_messages, :message_content],
  log_level: :info
)

# Connect to REST proxy instead of direct Discord API
# This allows multiple workers to share rate limits
bot.enable_scalable_rest(
  proxy: {
    base_url: proxy_url,
    authorization: proxy_auth
  }
)

# Register health check endpoint
bot.on(:ready) do |event|
  puts "✅ Worker #{event.shard_id} ready"
  puts "   Connected to REST proxy at #{proxy_url}"

  # Check proxy health
  health = bot.scalable_rest.health_check rescue nil
  puts "   Proxy health: #{health&.dig(:healthy) ? '✅' : '❌'}"
end

# Simple echo functionality
bot.on(:message_create) do |event|
  next if event.author.bot?

  if event.content.start_with?('!echo ')
    text = event.content[6..-1]
    event.message.respond(content: "[Worker] #{text}")
  end
end

puts "🚀 Starting REST proxy worker..."
puts "   Proxy: #{proxy_url}"
puts "   This worker connects to a central REST proxy for horizontal scaling"
bot.run
