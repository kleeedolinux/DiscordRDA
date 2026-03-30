# DiscordRDA Architecture

This document describes the architecture of DiscordRDA.

## Overview

DiscordRDA follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────┐
│           Application               │
├─────────────────────────────────────┤
│           Plugin Layer              │
├─────────────────────────────────────┤
│          Event System               │
├─────────────────────────────────────┤
│    Entity Layer (Factory Pattern)   │
├─────────────────────────────────────┤
│   Connection (Gateway + REST)       │
├─────────────────────────────────────┤
│     Cache + Rate Limiting           │
├─────────────────────────────────────┤
│        Core Runtime                 │
└─────────────────────────────────────┘
```

## Core Layer

### AsyncRuntime

Wraps Ruby 3.0+ Fiber scheduler for true async/await concurrency.

```ruby
runtime = DiscordRDA::AsyncRuntime.new
runtime.async { perform_io }
runtime.run
```

### Configuration

Immutable configuration with sensible defaults.

```ruby
config = DiscordRDA::Configuration.new(
  token: token,
  shards: :auto,
  intents: [:guilds]
)
```

### Logger

Structured logging with async-safe output.

```ruby
logger = DiscordRDA::Logger.new(level: :info, format: :structured)
logger.info('Event occurred', user_id: user.id)
```

### Snowflake

Discord ID value object with timestamp extraction.

```ruby
snowflake = DiscordRDA::Snowflake.new('1234567890123456789')
snowflake.timestamp  # => Time
snowflake.to_i       # => 1234567890123456789
```

## Entity Layer

### Factory Pattern

Entities are created through the factory for consistency:

```ruby
user = DiscordRDA::EntityFactory.create(:user, api_data)
guild = DiscordRDA::EntityFactory.create(:guild, api_data)
```

### Base Entity

All entities inherit from `Entity`:

- Immutable (frozen after creation)
- Lazy loading for related data
- JSON serialization support

### Entity Types

- `User`: Discord users (account-wide)
- `Guild`: Discord servers
- `Channel`: Text, voice, DM, thread channels
- `Message`: Discord messages
- `Role`: Guild roles
- `Member`: Guild members (User + guild data)
- `Emoji`: Custom and Unicode emojis
- `Attachment`: Message attachments
- `Embed`: Message embeds

## Connection Layer

### Gateway Client

WebSocket connection to Discord Gateway:

- zlib-stream compression
- Heartbeat management
- Resume/reconnect logic
- Identify payload construction

### REST Client

HTTP client for Discord REST API:

- Persistent connections
- Request/response interceptors
- Exponential backoff retry

### Rate Limiter

Token bucket algorithm per route:

- Per-route rate limits
- Global rate limit handling
- 429 response handling

### Shard Manager

Automatic and manual sharding:

```ruby
manager = DiscordRDA::ShardManager.new(config, event_bus, logger)
manager.calculate_shard_count(:auto, rest_client)
manager.start
```

## Event Layer

### Event Bus

Publish-subscribe event system:

```ruby
bus = DiscordRDA::EventBus.new
bus.on(:message_create) { |e| handle_message(e) }
bus.publish(:message_create, event)
```

### Event Types

- `READY`: Bot connected
- `MESSAGE_CREATE`: New message
- `GUILD_CREATE`: Guild available
- `INTERACTION_CREATE`: Slash command used
- And many more...

### Middleware

Chain middleware for event processing:

```ruby
class LoggingMiddleware < DiscordRDA::Middleware
  def call(event)
    puts "Event: #{event.type}"
    yield
  end
end

bus.use(LoggingMiddleware.new)
```

## Cache Layer

### Cache Store Interface

```ruby
class MyCache < DiscordRDA::CacheStore
  def get(key); end
  def set(key, value, ttl: nil); end
end
```

### Implementations

- `MemoryStore`: LRU in-memory cache
- `RedisStore`: Distributed Redis cache

### Entity Cache

Typed entity caching with automatic invalidation:

```ruby
cache = DiscordRDA::EntityCache.new(store)
cache.cache_user(user)
cache.user(user_id)
```

## Plugin Layer

### Base Plugin

```ruby
class MyPlugin < DiscordRDA::Plugin
  command 'hello', description: 'Say hello' do |ctx|
    ctx.respond(content: 'Hello!')
  end
end
```

### Plugin Registry

Manages loaded plugins:

```ruby
registry = DiscordRDA::PluginRegistry.new
registry.register(plugin, bot)
```

## Design Principles

1. **Immutable by Default**: Frozen objects prevent accidental mutation
2. **Lazy Loading**: Related data loads on demand
3. **Zero-Cost Abstractions**: No unnecessary wrapping
4. **Async-First**: All I/O is non-blocking
5. **Modular**: Components work independently
6. **Well-Documented**: Documentation is first-class

## Performance

Targets:
- 1000+ events/second per shard
- < 100MB memory per 1000 guilds
- < 5 second connection resumption

## Error Handling

Hierarchical error structure:

- `APIError`: Base API error
  - `BadRequestError`: 400
  - `UnauthorizedError`: 401
  - `ForbiddenError`: 403
  - `NotFoundError`: 404
  - `RateLimitedError`: 429
  - `ServerError`: 500+

## Security

- Token storage via environment variables
- Permission calculation helpers
- Rate limit compliance
