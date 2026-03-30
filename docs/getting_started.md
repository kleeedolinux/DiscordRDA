# Getting Started with DiscordRDA

This guide will help you get started building Discord bots with DiscordRDA.

## Installation

Add to your Gemfile:

```ruby
gem 'discord_rda'
```

Then run:

```bash
bundle install
```

## Your First Bot

Create a file called `bot.rb`:

```ruby
require 'discord_rda'

bot = DiscordRDA::Bot.new(
  token: ENV['DISCORD_TOKEN'],
  intents: [:guilds, :guild_messages, :message_content]
)

bot.on(:message_create) do |event|
  if event.content == '!hello'
    event.message.respond(content: 'Hello, World!')
  end
end

bot.run
```

Run it:

```bash
DISCORD_TOKEN=your_token_here ruby bot.rb
```

## Understanding the Architecture

DiscordRDA is built on several layers:

1. **Core Layer**: Async runtime, logging, configuration
2. **Entity Layer**: Discord objects (User, Guild, Message, etc.)
3. **Connection Layer**: Gateway (WebSocket) and REST (HTTP)
4. **Event Layer**: Event bus for handling Discord events
5. **Cache Layer**: Entity caching (memory or Redis)
6. **Plugin Layer**: Modular extensions

## Events

DiscordRDA uses an event-driven architecture. Events are dispatched through the event bus:

```ruby
# Handle all message creation
bot.on(:message_create) do |event|
  puts "New message: #{event.content}"
end

# Handle once (unsubscribes after first event)
bot.once(:ready) do |event|
  puts "Bot ready!"
end

# Wait for specific event
user = bot.wait_for(:message_create, timeout: 30) do |e|
  e.content.start_with?('!join')
end
```

## Working with Entities

Entities are immutable data objects:

```ruby
# Get a guild
guild = bot.guild('123456789')
puts guild.name

# Get a channel
channel = bot.channel('987654321')

# Send a message
bot.send_message('987654321', content: 'Hello!')
```

## Caching

DiscordRDA automatically caches entities:

```ruby
# Cached entities are returned instantly
guild = bot.guild('123456789')  # Fetched from API and cached
guild = bot.guild('123456789')  # Returned from cache

# Cache statistics
stats = bot.cache.stats
```

## Sharding

For large bots, use automatic sharding:

```ruby
bot = DiscordRDA::Bot.new(
  token: token,
  shards: :auto,
  intents: [:guilds, :guild_messages]
)
```

Or specify manually:

```ruby
bot = DiscordRDA::Bot.new(
  token: token,
  shards: [[0, 4], [1, 4], [2, 4], [3, 4]],
  intents: [:guilds, :guild_messages]
)
```

## Plugins

Create reusable functionality with plugins:

```ruby
class ModerationPlugin < DiscordRDA::Plugin
  command 'kick', description: 'Kick a user' do |ctx|
    user = ctx.options['user']
    ctx.respond(content: "Kicked #{user.mention}")
  end
end

bot.register_plugin(ModerationPlugin.new)
```

## Configuration Options

```ruby
bot = DiscordRDA::Bot.new(
  token: token,
  shards: :auto,                    # or explicit shard array
  cache: :memory,                   # or :redis
  intents: [:guilds],               # array of intents
  log_level: :info,                 # :debug, :info, :warn, :error
  max_reconnect_delay: 60.0,        # seconds
  enable_resume: true               # session resumption
)
```

## Next Steps

- Check the [examples](../examples/) directory
- Read the API reference
- Join the Discord community

## Common Issues

### Intents

Make sure to enable required intents in the Discord Developer Portal:
- `MESSAGE_CONTENT` for reading message content
- `GUILD_MEMBERS` for member events

### Rate Limits

DiscordRDA handles rate limits automatically. Respect Discord's terms of service.

### Errors

```ruby
bot.on(:error) do |event|
  puts "Error: #{event.error}"
end
```
