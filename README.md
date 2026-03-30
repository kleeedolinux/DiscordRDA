# DiscordRDA

> Modern, scalable Ruby library for Discord bot development with full Slash Commands and Component V2 support

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%203.0-red.svg)](https://www.ruby-lang.org/)

DiscordRDA (Ruby Development API) is a high-performance Ruby library for building Discord bots with modern async patterns, comprehensive Slash Command support, Component V2 architecture, and enterprise-grade scalability features.

## Features

### Core Capabilities
- **⚡ Async Runtime**: Built on Ruby 3.0+ Fiber scheduler for true concurrency
- **🏭 Factory Pattern**: Clean entity creation with `EntityFactory`
- **📡 Auto Sharding**: Automatic and manual sharding with zero-downtime resharding
- **💾 Pluggable Cache**: Memory or Redis backends with pattern-based invalidation
- **🔌 Plugin System**: Extensible architecture for commands and features
- **📊 Rate Limiting**: Advanced Discord API rate limit handling with queue management
- **🎯 Full Documentation**: Every API is fully documented

### Slash Commands & Interactions
- **Full Slash Command API**: Create, edit, delete global and guild commands
- **Context Menu Commands**: User and Message context menu support
- **Autocomplete**: Real-time autocomplete with dynamic choices
- **Modals**: Custom modal forms with text inputs
- **Component V2**: Latest Discord components (buttons, selects, containers)

### Enterprise Features
- **Zero-Downtime Resharding**: Add shards without stopping the bot
- **Hot Reload**: File system event-based code reloading
- **Session Transfer**: Migrate guilds between shards seamlessly
- **REST Proxy Support**: Horizontal scaling with proxy servers
- **State Preservation**: Maintain sessions across reloads

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'discord_rda'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install discord_rda
```

## Quick Start

```ruby
require 'discord_rda'

bot = DiscordRDA::Bot.new(
  token: ENV['DISCORD_TOKEN'],
  intents: [:guilds, :guild_messages, :message_content]
)

bot.on(:message_create) do |event|
  if event.content == '!ping'
    event.message.respond(content: 'Pong!')
  end
end

bot.run
```

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Slash Commands](#slash-commands)
- [Components](#components)
- [Interactions](#interactions)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Sharding](#sharding)
- [Caching](#caching)
- [Rate Limiting](#rate-limiting)
- [Plugin System](#plugin-system)
- [Development](#development)
- [License](#license)

## Slash Commands

DiscordRDA provides a comprehensive DSL for building Slash Commands:

### Basic Slash Command

```ruby
bot.slash('hello', 'Say hello') do |cmd|
  cmd.string('name', 'Your name', required: true)
  cmd.handler do |interaction|
    name = interaction.option('name')
    interaction.respond(content: "Hello, #{name}!")
  end
end
```

### Command with Multiple Options

```ruby
bot.slash('ban', 'Ban a user from the server') do |cmd|
  cmd.user('user', 'User to ban', required: true)
  cmd.string('reason', 'Reason for ban')
  cmd.integer('days', 'Days of messages to delete')
  cmd.default_permissions(:ban_members)
  
  cmd.handler do |interaction|
    user = interaction.option('user')
    reason = interaction.option('reason') || 'No reason provided'
    interaction.respond(content: "Banned #{user.username}", ephemeral: true)
  end
end
```

### Guild-Specific Commands

```ruby
bot.slash('admin', 'Admin only command', guild_id: '123456789') do |cmd|
  cmd.default_permissions(:administrator)
  cmd.handler do |interaction|
    interaction.respond(content: 'Admin command executed!', ephemeral: true)
  end
end
```

### Context Menu Commands

```ruby
# User context menu
bot.context_menu(type: :user, name: 'High Five') do |interaction|
  user = interaction.target_user
  interaction.respond(content: "High-fived #{user.username}!")
end
```

## Components

### Button Components

```ruby
interaction.respond(content: 'Click the button!') do |builder|
  builder.components do |row|
    row.button(style: :primary, label: 'Click Me', custom_id: 'click_button')
    row.button(style: :danger, label: 'Delete', custom_id: 'delete_button')
    row.button(style: :link, label: 'Docs', url: 'https://example.com')
  end
end

# Handle button clicks
bot.on(:button_click) do |interaction|
  interaction.respond(content: 'Button clicked!', ephemeral: true)
end
```

### Select Menus

```ruby
interaction.respond(content: 'Select your roles:') do |builder|
  builder.components do |row|
    row.string_select(
      custom_id: 'role_select',
      placeholder: 'Choose roles',
      options: [
        { label: 'Admin', value: 'admin' },
        { label: 'Mod', value: 'mod' }
      ]
    )
  end
end
```

## Interactions

### Deferred Responses

```ruby
bot.slash('slow', 'A slow command') do |cmd|
  cmd.handler do |interaction|
    interaction.defer(ephemeral: true)
    # Do slow work
    sleep(5)
    interaction.edit_original(content: 'Done!')
  end
end
```

### Modals

```ruby
bot.slash('feedback', 'Submit feedback') do |cmd|
  cmd.handler do |interaction|
    interaction.modal(custom_id: 'feedback_modal', title: 'Send Feedback') do |modal|
      modal.short(custom_id: 'subject', label: 'Subject', required: true)
      modal.paragraph(custom_id: 'message', label: 'Your feedback', required: true)
    end
  end
end

# Handle modal submission
bot.on(:modal_submit) do |interaction|
  subject = interaction.modal_value('subject')
  message = interaction.modal_value('message')
  interaction.respond(content: 'Thank you!', ephemeral: true)
end
```

## Documentation

- [Getting Started](docs/getting_started.md)
- [Architecture](docs/architecture.md)
- [API Reference](https://rubydoc.info/github/juliaklee/discord_rda)

## Examples

See the [examples](examples/) directory:

- `basic_bot.rb` - Simple echo bot
- `sharded_bot.rb` - Multi-shard example
- `plugin_bot.rb` - Custom plugin demonstration
- `slash_command_bot.rb` - Slash command handling

## Architecture

DiscordRDA follows a layered architecture designed for scalability:

```
┌─────────────────────────────────────────────────────────────┐
│                      Application Layer                       │
│  (Your bot code, commands, event handlers, plugins)         │
├─────────────────────────────────────────────────────────────┤
│                      Interaction Layer                       │
│  (Slash commands, components, modals, autocomplete)         │
├─────────────────────────────────────────────────────────────┤
│                      Entity Layer                            │
│  (User, Message, Guild, Channel - Factory Pattern)         │
├─────────────────────────────────────────────────────────────┤
│                      Event System                            │
│  (EventBus, subscriptions, middleware chain)               │
├─────────────────────────────────────────────────────────────┤
│                    Connection Layer                          │
│  (Gateway WebSocket, REST API client)                      │
├─────────────────────────────────────────────────────────────┤
│                     Scalability Layer                        │
│  (Rate limiting, sharding, hot reload, caching)            │
├─────────────────────────────────────────────────────────────┤
│                      Core Runtime                            │
│  (Async scheduler, configuration, logging)                 │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Immutable by Default**: Entities are frozen after creation for thread safety
2. **Async-First**: All I/O operations are non-blocking using Ruby's Fiber scheduler
3. **Type Safety**: Full type coercion with attributes system
4. **Zero-Cost Abstractions**: No unnecessary object allocations
5. **Extensibility**: Plugin system for modular functionality

## Configuration

### Basic Configuration

```ruby
bot = DiscordRDA::Bot.new(
  token: ENV['DISCORD_TOKEN'],
  application_id: ENV['DISCORD_APP_ID'],
  shards: :auto,
  cache: :redis,
  intents: [:guilds, :guild_messages, :message_content],
  log_level: :info,
  log_format: :json
)
```

### Advanced Configuration

```ruby
bot = DiscordRDA::Bot.new(
  token: ENV['DISCORD_TOKEN'],
  shards: [[0, 4], [1, 4]],
  cache: :redis,
  redis_config: { host: 'localhost', port: 6379 },
  enable_scalable_rest: true,
  intents: [:guilds, :guild_members, :guild_messages, :message_content]
)
```

## Sharding

### Automatic Sharding

```ruby
bot = DiscordRDA::Bot.new(token: token, shards: :auto)
```

### Zero-Downtime Resharding

```ruby
# Enable auto-resharding
bot.enable_auto_reshard(max_guilds_per_shard: 1000)

# Manual resharding
bot.reshard_to(8)
```

## Caching

### Memory Cache (Default)

```ruby
bot = DiscordRDA::Bot.new(token: token, cache: :memory, max_cache_size: 10000)
```

### Redis Cache

```ruby
bot = DiscordRDA::Bot.new(
  token: token,
  cache: :redis,
  redis_config: { host: 'localhost', port: 6379 }
)
```

### Cache Invalidation

```ruby
bot.cache.invalidate(:user, user_id)
bot.cache.invalidate_guild(guild_id)
bot.cache.clear
```

## Rate Limiting

DiscordRDA includes advanced rate limit management:

```ruby
# Enable scalable REST (recommended for production)
bot.enable_scalable_rest

# Check invalid request bucket status
status = bot.invalid_bucket_status
```

## Plugin System

### Creating a Plugin

```ruby
class MusicPlugin < DiscordRDA::Plugin
  def setup(bot)
    @bot = bot
  end
  
  def ready(bot)
    bot.logger.info('Music plugin ready')
  end
end

bot.register_plugin(MusicPlugin.new)
```

## Development

### Hot Reload

```ruby
bot = DiscordRDA::Bot.new(token: token)
bot.enable_hot_reload(watch_dir: 'lib')
```

### Running Tests

```bash
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub.

## License

Licensed under the [MIT License](LICENSE).

Copyright (c) 2026 Júlia Klee

## Acknowledgments

Created by Júlia Klee. Inspired by DiscordJDA and other Discord libraries. Special thanks to the Ruby async community and Discord API documentation contributors.
