# frozen_string_literal: true

require 'discord_rda'

# Basic echo bot example
# This bot responds to "!ping" with "Pong!"

# Get token from environment variable
token = ENV['DISCORD_TOKEN']

unless token
  puts 'Please set DISCORD_TOKEN environment variable'
  exit 1
end

# Create bot instance
bot = DiscordRDA::Bot.new(
  token: token,
  intents: [:guilds, :guild_messages, :message_content],
  log_level: :info
)

# Handle message creation events
bot.on(:message_create) do |event|
  # Ignore messages from bots
  next if event.author.bot?

  # Echo command
  if event.content == '!ping'
    event.message.respond(content: 'Pong!')
  end

  # Echo command - repeat message
  if event.content.start_with?('!echo ')
    text = event.content[6..-1]
    event.message.respond(content: text)
  end

  # Info command
  if event.content == '!info'
    info = [
      "**Bot Info**",
      "Library: DiscordRDA",
      "Shard: #{event.shard_id}",
      "Channel: <##{event.channel_id}>"
    ].join("\n")

    event.message.respond(content: info)
  end
end

# Handle ready event
bot.once(:ready) do |event|
  puts "✅ Bot logged in as #{event.user&.display_name}"
  puts "   Guilds: #{event.guilds.length}"
end

# Run the bot
puts "🚀 Starting basic bot..."
bot.run
