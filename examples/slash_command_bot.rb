# frozen_string_literal: true

require 'discord_rda'

# Slash command bot example
# Demonstrates slash command handling

token = ENV['DISCORD_TOKEN']

unless token
  puts 'Please set DISCORD_TOKEN environment variable'
  exit 1
end

bot = DiscordRDA::Bot.new(
  token: token,
  intents: [:guilds, :guild_messages],
  log_level: :info
)

# Register slash commands
bot.register_command('ping', 'Check bot latency') do |ctx|
  latency = (Time.now.to_f * 1000).to_i
  ctx.respond(content: "Pong! Latency: #{latency}ms")
end

bot.register_command('userinfo', 'Get user information', [
  { name: 'user', description: 'Target user', type: :user, required: false }
]) do |ctx|
  user = ctx.options['user'] || ctx.user

  info = [
    "**#{user.display_name}**",
    "ID: #{user.id}",
    "Created: #{user.created_at.strftime('%Y-%m-%d')}"
  ].join("\n")

  ctx.respond(content: info)
end

bot.register_command('roll', 'Roll a die', [
  { name: 'sides', description: 'Number of sides', type: :integer, required: false }
]) do |ctx|
  sides = ctx.options['sides'] || 6
  result = rand(1..sides)
  ctx.respond(content: "🎲 Rolled **#{result}** (1-#{sides})")
end

# Handle interaction events
bot.on(:interaction_create) do |event|
  next unless event.command?

  data = event.data['data']
  command_name = data['name']

  puts "Received command: #{command_name}"
end

bot.once(:ready) do |event|
  puts "✅ Slash command bot ready!"
  puts "   Commands: ping, userinfo, roll"
end

puts "🚀 Starting slash command bot..."
bot.run
