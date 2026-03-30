# frozen_string_literal: true

require 'discord_rda'

# Custom plugin example
# Demonstrates the plugin system

# Define a custom plugin
class ModerationPlugin < DiscordRDA::Plugin
  name 'Moderation'
  version '1.0.0'
  description 'Basic moderation commands'

  command 'kick',
    description: 'Kick a user from the guild',
    options: [
      { name: 'user', description: 'User to kick', type: :user, required: true },
      { name: 'reason', description: 'Reason for kick', type: :string, required: false }
    ] do |ctx|
    # Kick implementation would go here
    ctx.respond(content: "Kicked #{ctx.options['user']}")
  end

  command 'ban',
    description: 'Ban a user from the guild',
    options: [
      { name: 'user', description: 'User to ban', type: :user, required: true },
      { name: 'reason', description: 'Reason for ban', type: :string, required: false },
      { name: 'days', description: 'Days of messages to delete', type: :integer, required: false }
    ] do |ctx|
    # Ban implementation would go here
    ctx.respond(content: "Banned #{ctx.options['user']}")
  end

  on :message_create do |event|
    # Auto-moderation example: delete messages with banned words
    # This is just a demonstration
  end
end

# Utility plugin
class UtilityPlugin < DiscordRDA::Plugin
  name 'Utility'
  version '1.0.0'
  description 'Utility commands'

  command 'avatar',
    description: 'Get user avatar',
    options: [
      { name: 'user', description: 'User (default: self)', type: :user, required: false }
    ] do |ctx|
    user = ctx.options['user'] || ctx.user
    ctx.respond(content: "Avatar: #{user.avatar_url}")
  end

  command 'serverinfo',
    description: 'Get server information' do |ctx|
    guild = ctx.guild
    info = [
      "**#{guild.name}**",
      "Members: #{guild.member_count}",
      "Boost Level: #{guild.premium_tier_name}",
      "Created: #{guild.created_at.strftime('%Y-%m-%d')}"
    ].join("\n")

    ctx.respond(content: info)
  end
end

token = ENV['DISCORD_TOKEN']

unless token
  puts 'Please set DISCORD_TOKEN environment variable'
  exit 1
end

# Create bot
bot = DiscordRDA::Bot.new(
  token: token,
  intents: [:guilds, :guild_messages, :message_content],
  log_level: :info
)

# Register plugins
bot.register_plugin(ModerationPlugin.new)
bot.register_plugin(UtilityPlugin.new)

puts "📦 Registered plugins:"
bot.plugins.all.each do |plugin|
  puts "  - #{plugin.name} v#{plugin.version}"
end

# Run bot
puts "🚀 Starting plugin bot..."
bot.run
