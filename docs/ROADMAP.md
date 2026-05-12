# DiscordRDA Scalability & API Roadmap

This document provides a complete status of DiscordRDA implementation.

**Legend:**
- ✅ Fully Implemented - Production ready
- ⚠️ Simplified - Basic implementation, needs enhancement
- 🔄 Partial - Some features implemented, others missing
- ❌ Not Implemented - Placeholder or not started
- 📝 Planned - On the roadmap

---

## Core Scalability Goals (Discordeno-Inspired)

### Rate Limiting & Request Management

| Feature | Status | Notes |
|---------|--------|-------|
| **Invalid Request Bucket** | ✅ Implemented | Tracks 401/403/429/502 with global pause protection |
| **Request Queue System** | ✅ Implemented | Full async integration with timeouts and retry logic |
| **URL Simplification** | ✅ Implemented | Route bucket identification working |
| **Rate Limit Processing Loop** | ✅ Implemented | Precise async timer-based resets |
| **Global Rate Limit Handling** | ✅ Implemented | Detects and handles X-RateLimit-Global |
| **Bucket ID Tracking** | ✅ Implemented | Tracks Discord rate limit buckets |
| **Queue Auto-Cleanup** | ✅ Implemented | Deletes empty queues after delay |

### Scalability Features

| Feature | Status | Notes |
|---------|--------|-------|
| **Zero-Downtime Resharding** | ✅ Implemented | Guild transfer and session migration |
| **Session Transfer** | ✅ Implemented | Real guild data migration |
| **Auto-Resharding** | ✅ Implemented | Triggers on guild count thresholds |
| **REST Proxy Support** | ✅ Implemented | Client and proxy configuration support |
| **Horizontal Scaling** | ✅ Implemented | Distributed state sync via proxy |
| **Hot Reload** | ✅ Implemented | Listen gem with file system events |
| **State Preservation** | ✅ Implemented | Session IDs and sequences preserved across reloads |
| **Instant Restarts** | 🔄 Partial | Needs process manager integration for true zero-downtime |

### Caching System

| Feature | Status | Notes |
|---------|--------|-------|
| **Cache Nothing (Default)** | ✅ Implemented | `ConfigurableCache` with `:none` strategy |
| **Full Cache Strategy** | ✅ Implemented | `ConfigurableCache` with `:full` strategy |
| **Custom Cache Strategy** | ✅ Implemented | Selective entity and property caching |
| **Memory Store** | ✅ Implemented | LRU cache with TTL |
| **Redis Store** | ✅ Implemented | Redis backend with serialization |
| **Cache Property Filtering** | ✅ Implemented | Advanced filtering with transforms and batch operations |
| **Cache Invalidation** | ✅ Implemented | Pattern-based key scanning |
| **Entity Cache** | ✅ Implemented | Typed entity cache with TTL |

### Analytics & Monitoring

| Feature | Status | Notes |
|---------|--------|-------|
| **Metrics Collection** | ✅ Implemented | Gateway/REST/Cache/Shard metrics |
| **Pretty Reports** | ✅ Implemented | Formatted text output |
| **Dashboard Data** | ✅ Implemented | JSON API for dashboards |
| **Health Checks** | ✅ Implemented | Comprehensive health monitoring with status reporting |
| **Real-time Analytics** | ✅ Implemented | Per-second event tracking |
| **Prometheus Export** | ❌ Not Implemented | Planned for enterprise tier |
| **Grafana Integration** | ❌ Not Implemented | Planned for enterprise tier |

---

## Discord API Implementation Status

### Gateway (WebSocket)

| Feature | Status | Notes |
|---------|--------|-------|
| **Gateway Connection** | ✅ Implemented | Full WebSocket with compression |
| **Heartbeat Handling** | ✅ Implemented | Heartbeat ACK tracking |
| **Session Resume** | ✅ Implemented | Resume with session_id and sequence |
| **Session Reconnect** | ✅ Implemented | Automatic reconnection |
| **zlib-stream Compression** | ✅ Implemented | Discord compression support |
| **Sharding** | ✅ Implemented | Manual and automatic sharding |
| **Intents** | ✅ Implemented | All Discord intents supported |
| **Presence Updates** | ✅ Implemented | Status and activity updates |
| **Guild Member Chunking** | ✅ Implemented | Request guild members |
| **Voice Gateway** | ❌ Not Implemented | Voice connection not started |

### REST API - Channels

| Feature | Status | Notes |
|---------|--------|-------|
| **Get Channel** | ✅ Implemented | Basic fetch |
| **Modify Channel** | ✅ Implemented | Full DSL with ChannelBuilder |
| **Delete Channel** | ✅ Implemented | Delete request |
| **Get Channel Messages** | ✅ Implemented | Full pagination with before/after/around, iterator support |
| **Get Channel Message** | ✅ Implemented | Single message fetch |
| **Create Message** | ✅ Implemented | Full components support with MessageBuilder |
| **Crosspost Message** | ✅ Implemented | `Bot#crosspost_message` |
| **Create Reaction** | ✅ Implemented | Full unicode and custom emoji support |
| **Delete Reaction** | ✅ Implemented | Remove own or others' reactions |
| **Get Reactions** | ✅ Implemented | Full reaction list with pagination support |
| **Delete All Reactions** | ✅ Implemented | Clear all reactions from message |
| **Edit Message** | ✅ Implemented | PATCH message |
| **Delete Message** | ✅ Implemented | Delete request |
| **Bulk Delete Messages** | ✅ Implemented | Bulk delete endpoint with reason support |
| **Edit Channel Permissions** | ✅ Implemented | `Bot#edit_channel_permissions` |
| **Get Channel Invites** | ✅ Implemented | `Bot#channel_invites` |
| **Create Channel Invite** | ✅ Implemented | `Bot#create_channel_invite` with `InviteBuilder` |
| **Delete Channel Permission** | ✅ Implemented | `Bot#delete_channel_permission` |
| **Follow News Channel** | ✅ Implemented | `Bot#follow_news_channel` |
| **Trigger Typing Indicator** | ✅ Implemented | `Bot#trigger_typing` |
| **Get Pinned Messages** | ✅ Implemented | `Bot#pinned_messages` |
| **Pin Message** | ✅ Implemented | `Bot#pin_message` and `Message#pin` |
| **Unpin Message** | ✅ Implemented | `Bot#unpin_message` and `Message#unpin` |
| **Group DM Add Recipient** | ❌ Not Implemented | |
| **Group DM Remove Recipient** | ❌ Not Implemented | |
| **Start Thread from Message** | ✅ Implemented | `Bot#start_thread_from_message` |
| **Start Thread without Message** | ✅ Implemented | `Bot#start_thread` |
| **Join Thread** | ✅ Implemented | `Bot#join_thread` |
| **Add Thread Member** | ✅ Implemented | `Bot#add_thread_member` |
| **Leave Thread** | ✅ Implemented | `Bot#leave_thread` |
| **Remove Thread Member** | ✅ Implemented | `Bot#remove_thread_member` |
| **Get Thread Member** | ✅ Implemented | `Bot#thread_member` |
| **List Thread Members** | ✅ Implemented | `Bot#thread_members` |
| **List Public Archived Threads** | ✅ Implemented | `Bot#archived_threads(scope: :public)` |
| **List Private Archived Threads** | ✅ Implemented | `Bot#archived_threads(scope: :private)` |
| **List Joined Private Archived Threads** | ✅ Implemented | `Bot#archived_threads(scope: :joined_private)` |

### REST API - Guilds

| Feature | Status | Notes |
|---------|--------|-------|
| **Create Guild** | ✅ Implemented | Full guild creation |
| **Get Guild** | ✅ Implemented | Guild fetch with caching |
| **Get Guild Preview** | ✅ Implemented | `Bot#guild_preview` and `Guild#fetch_preview` |
| **Modify Guild** | ✅ Implemented | Full guild modification |
| **Delete Guild** | ✅ Implemented | |
| **Get Guild Channels** | ✅ Implemented | List guild channels with full data |
| **Create Guild Channel** | ✅ Implemented | Full channel creation with ChannelBuilder |
| **Modify Guild Channel** | ✅ Implemented | Position updates and full modification |
| **Delete Guild Channel** | ✅ Implemented | Channel deletion with reason support |
| **Get Guild Member** | ✅ Implemented | Fetch single member with caching |
| **List Guild Members** | ✅ Implemented | Pagination with limit/after/before support |
| **Search Guild Members** | ✅ Implemented | Query-based search with full filtering |
| **Add Guild Member** | ❌ Not Implemented | OAuth2 add member |
| **Modify Guild Member** | ✅ Implemented | Nick, roles, voice state, timeout support |
| **Modify Current Member** | ❌ Not Implemented | Modify self nickname |
| **Modify Current User Nick** | ❌ Not Implemented | Modify self nickname |
| **Add Guild Member Role** | ✅ Implemented | Add role to member with audit log |
| **Remove Guild Member Role** | ✅ Implemented | Remove role from member with audit log |
| **Remove Guild Member** | ✅ Implemented | Kick member with reason and audit log |
| **Get Guild Bans** | ✅ Implemented | List bans with full pagination |
| **Get Guild Ban** | ✅ Implemented | Fetch single ban with user data |
| **Create Guild Ban** | ✅ Implemented | Ban with message delete days and audit log |
| **Remove Guild Ban** | ✅ Implemented | Unban user with audit log |
| **Get Guild Roles** | ✅ Implemented | List all roles with full data |
| **Get Guild Role** | ✅ Implemented | Via role_objects/role methods |
| **Create Guild Role** | ✅ Implemented | Full role creation with all options |
| **Modify Guild Role** | ✅ Implemented | Full role editing with all properties |
| **Modify Guild Role Positions** | ❌ Not Implemented | |
| **Delete Guild Role** | ✅ Implemented | Delete role with full audit log |
| **Get Guild Prune Count** | ✅ Implemented | `Bot#guild_prune_count` |
| **Begin Guild Prune** | ✅ Implemented | `Bot#begin_guild_prune` |
| **Get Guild Voice Regions** | ✅ Implemented | `Bot#guild_voice_regions` and `Guild#fetch_voice_regions` |
| **Get Guild Invites** | ✅ Implemented | `Bot#guild_invites` and `Guild#fetch_invites` |
| **Get Guild Integrations** | ✅ Implemented | `Bot#guild_integrations` and `Guild#fetch_integrations` |
| **Delete Guild Integration** | ✅ Implemented | `Bot#delete_guild_integration` |
| **Get Guild Widget Settings** | ✅ Implemented | `Bot#guild_widget_settings` and `Guild#fetch_widget_settings` |
| **Modify Guild Widget** | ✅ Implemented | `Bot#modify_guild_widget` |
| **Get Guild Widget** | ✅ Implemented | `Bot#guild_widget` |
| **Get Guild Vanity URL** | ✅ Implemented | `Bot#guild_vanity_url` |
| **Get Guild Widget Image** | ✅ Implemented | `Bot#guild_widget_image` |
| **Get Guild Welcome Screen** | ✅ Implemented | `Bot#guild_welcome_screen` and `Guild#fetch_welcome_screen` |
| **Modify Guild Welcome Screen** | ✅ Implemented | `Bot#modify_guild_welcome_screen` |
| **Get Guild Onboarding** | ✅ Implemented | `Bot#guild_onboarding` and `Guild#fetch_onboarding` |
| **Modify Guild Onboarding** | ✅ Implemented | `Bot#modify_guild_onboarding` |

### REST API - Interactions (Slash Commands)

| Feature | Status | Notes |
|---------|--------|-------|
| **Create Global Command** | ✅ Implemented | Full DSL with CommandBuilder |
| **Get Global Command** | ✅ Implemented | Via REST client |
| **Edit Global Command** | ✅ Implemented | Full edit support |
| **Delete Global Command** | ✅ Implemented | REST endpoint |
| **Bulk Overwrite Global Commands** | ✅ Implemented | bulk_register_commands method |
| **Get Guild Commands** | ✅ Implemented | Via REST client |
| **Create Guild Command** | ✅ Implemented | Guild-specific registration |
| **Get Guild Command** | ✅ Implemented | Via REST client |
| **Edit Guild Command** | ✅ Implemented | Full edit support |
| **Delete Guild Command** | ✅ Implemented | REST endpoint |
| **Bulk Overwrite Guild Commands** | ✅ Implemented | Guild bulk endpoint |
| **Get Guild Command Permissions** | ✅ Implemented | Via ApplicationCommand |
| **Edit Guild Command Permissions** | ✅ Implemented | Via ApplicationCommand |
| **Batch Edit Guild Command Permissions** | ✅ Implemented | Via REST client |
| **Create Interaction Response** | ✅ Implemented | All response types |
| **Get Original Interaction Response** | ✅ Implemented | edit_original method |
| **Edit Original Interaction Response** | ✅ Implemented | Full edit support |
| **Delete Original Interaction Response** | ✅ Implemented | delete_original method |
| **Create Followup Message** | ✅ Implemented | followup method |
| **Get Followup Message** | ✅ Implemented | get_followup method |
| **Edit Followup Message** | ✅ Implemented | edit_followup method |
| **Delete Followup Message** | ✅ Implemented | delete_followup method |
| **Autocomplete Response** | ✅ Implemented | autocomplete method |
| **Modal Response** | ✅ Implemented | modal method with ModalBuilder |

### REST API - Users

| Feature | Status | Notes |
|---------|--------|-------|
| **Get Current User** | ✅ Implemented | Bot user fetch |
| **Get User** | ✅ Implemented | Full fetch with guilds, DMs, connections support |
| **Modify Current User** | ✅ Implemented | `Bot#modify_current_user` and `User.modify_current_user` |
| **Get Current User Guilds** | ✅ Implemented | `Bot#current_user_guilds` and `User.get_current_user_guilds` |
| **Get Current User Guild Member** | ✅ Implemented | `Bot#current_user_guild_member` and `User.get_current_user_guild_member` |
| **Leave Guild** | ✅ Implemented | `Bot#leave_guild` and `User.leave_guild` |
| **Create DM** | ✅ Implemented | `Bot#create_dm` and `User#create_dm_channel` |
| **Get User Connections** | ✅ Implemented | `Bot#current_user_connections` and `User.get_connections` |
| **Get User Application Role Connection** | ✅ Implemented | `Bot#application_role_connection` and `User.get_application_role_connection` |
| **Update User Application Role Connection** | ✅ Implemented | `Bot#update_application_role_connection` and `User.update_application_role_connection` |

### REST API - Webhooks

| Feature | Status | Notes |
|---------|--------|-------|
| **Create Webhook** | ✅ Implemented | Create webhook in channel |
| **Get Channel Webhooks** | ✅ Implemented | List channel webhooks |
| **Get Guild Webhooks** | ✅ Implemented | List guild webhooks |
| **Get Webhook** | ✅ Implemented | `Bot#webhook` |
| **Get Webhook with Token** | ✅ Implemented | `Bot#webhook_with_token` |
| **Modify Webhook** | ✅ Implemented | `Bot#modify_webhook` |
| **Modify Webhook with Token** | ✅ Implemented | `Bot#modify_webhook_with_token` |
| **Delete Webhook** | ✅ Implemented | Delete webhook |
| **Delete Webhook with Token** | ✅ Implemented | `Bot#delete_webhook(token: ...)` |
| **Execute Webhook** | ✅ Implemented | Send message via webhook with components |
| **Execute Slack-Compatible Webhook** | ✅ Implemented | `Bot#execute_slack_webhook` |
| **Execute GitHub-Compatible Webhook** | ✅ Implemented | `Bot#execute_github_webhook` |
| **Get Webhook Message** | ✅ Implemented | `Bot#webhook_message` |
| **Edit Webhook Message** | ✅ Implemented | `Bot#edit_webhook_message` |
| **Delete Webhook Message** | ✅ Implemented | `Bot#delete_webhook_message` |

### REST API - OAuth2

| Feature | Status | Notes |
|---------|--------|-------|
| **Get Current Bot Application Info** | ✅ Implemented | `Bot#application_info` |
| **Get Current Authorization Info** | ✅ Implemented | `Bot#authorization_info` |

### REST API - Other

| Feature | Status | Notes |
|---------|--------|-------|
| **Get Gateway** | ✅ Implemented | |
| **Get Gateway Bot** | ✅ Implemented | Used for sharding |
| **Sticker Operations** | ❌ Not Implemented | |
| **Guild Scheduled Events** | ❌ Not Implemented | |
| **Guild Template Operations** | ❌ Not Implemented | |
| **Stage Instance Operations** | ❌ Not Implemented | |
| **Audit Log** | ❌ Not Implemented | |
| **Auto Moderation** | ❌ Not Implemented | |
| **Entitlements (Monetization)** | ❌ Not Implemented | |
| **SKU (Monetization)** | ❌ Not Implemented | |
| **Soundboard** | ❌ Not Implemented | |

---

## Entity Implementation Status

| Entity | Status | Properties | Methods |
|--------|--------|------------|---------|
| **User** | ✅ Complete | All basic props | avatar_url, mention, flags |
| **Guild** | ✅ Complete | Full properties with role/emoji helpers and API methods | icon_url, features check |
| **Channel** | ✅ Complete | Full properties with activity helpers and API methods | type helpers, mention |
| **Message** | ✅ Complete | Full properties with components support | reply tracking, jump_url |
| **Role** | ✅ Complete | Full properties with permissions helper | permissions, color, mention |
| **Member** | ✅ Complete | Full properties with display_name and permissions | display_name, permissions |
| **Emoji** | ✅ Complete | Custom & Unicode | url, mention, animated check |
| **Attachment** | ✅ Complete | All props | size formatting, dimensions |
| **Embed** | ✅ Complete | All types | Builder pattern |
| **Sticker** | ✅ Implemented | Full props, URL generation, guild sticker management |
| **Interaction** | ✅ Complete | Full slash command, component, modal support |
| **Interaction Event** | ✅ Implemented | Full event with interaction handler | |
| **Audit Log Entry** | ❌ Not Implemented | | |
| **Application** | ❌ Not Implemented | | |
| **Team** | ❌ Not Implemented | | |

---

## Event Implementation Status

| Event | Status | Handler |
|-------|--------|---------|
| **READY** | ✅ Implemented | User, guilds, session_id |
| **RESUMED** | ✅ Implemented | Acknowledgment |
| **CHANNEL_CREATE** | ✅ Implemented | Channel entity |
| **CHANNEL_UPDATE** | ✅ Implemented | Channel entity |
| **CHANNEL_DELETE** | ✅ Implemented | Channel entity |
| **Channel Pins Update** | ✅ Implemented | Full event with guild, timestamp |
| **GUILD_CREATE** | ✅ Implemented | Guild entity with availability |
| **GUILD_UPDATE** | ✅ Implemented | Guild entity |
| **GUILD_DELETE** | ✅ Implemented | Unavailable check |
| **Guild Ban Add** | ✅ Implemented | Full event with guild context |
| **Guild Ban Remove** | ✅ Implemented | Full event with guild context |
| **Guild Emojis Update** | ✅ Implemented | Full event with emoji changes |
| **GUILD_INTEGRATIONS_UPDATE** | ⚠️ Simplified | Basic event |
| **Guild Member Add** | ✅ Implemented | Full member with inviter data |
| **Guild Member Remove** | ✅ Implemented | Full event with guild context |
| **Guild Member Update** | ✅ Implemented | Full with role/nick changes |
| **Guild Members Chunk** | ✅ Implemented | Full members array with data |
| **Guild Role Create** | ✅ Implemented | Full role event |
| **Guild Role Update** | ✅ Implemented | Full with before/after |
| **Guild Role Delete** | ✅ Implemented | Full event with guild context |
| **MESSAGE_CREATE** | ✅ Implemented | Full Message entity |
| **Message Update** | ✅ Implemented | Full with changed fields tracking |
| **Message Delete** | ✅ Implemented | Full with author reconstruction |
| **Message Delete Bulk** | ✅ Implemented | Full with author grouping |
| **Message Reaction Add** | ✅ Implemented | Full with member, burst, super reaction |
| **Message Reaction Remove** | ✅ Implemented | Full with user context |
| **Message Reaction Remove All** | ✅ Implemented | Full with jump URL |
| **Message Reaction Remove Emoji** | ✅ Implemented | Full emoji context |
| **PRESENCE_UPDATE** | ⚠️ Simplified | Basic event |
| **TYPING_START** | ⚠️ Simplified | Basic event |
| **USER_UPDATE** | ⚠️ Simplified | User entity |
| **VOICE_STATE_UPDATE** | ⚠️ Simplified | Basic event |
| **VOICE_SERVER_UPDATE** | ⚠️ Simplified | Basic event |
| **WEBHOOKS_UPDATE** | ⚠️ Simplified | Basic event |
| **INTERACTION_CREATE** | ✅ Implemented | Full command system with subcommands, permissions, cooldowns |
| **STAGE_INSTANCE_CREATE** | ⚠️ Simplified | Basic event |
| **STAGE_INSTANCE_UPDATE** | ⚠️ Simplified | Basic event |
| **STAGE_INSTANCE_DELETE** | ⚠️ Simplified | Basic event |
| **THREAD_CREATE** | ✅ Implemented | Full with creator, guild context |
| **THREAD_UPDATE** | ✅ Implemented | Full with guild context |
| **THREAD_DELETE** | ✅ Implemented | Full with parent channel |
| **THREAD_LIST_SYNC** | ✅ Implemented | Full with threads array |
| **THREAD_MEMBER_UPDATE** | ✅ Implemented | Full member update |
| **THREAD_MEMBERS_UPDATE** | ✅ Implemented | Full with added/removed |
| **GUILD_SCHEDULED_EVENT_CREATE** | ✅ Implemented | Full event entity |
| **GUILD_SCHEDULED_EVENT_UPDATE** | ✅ Implemented | Full with status tracking |
| **GUILD_SCHEDULED_EVENT_DELETE** | ✅ Implemented | Full event entity |
| **GUILD_SCHEDULED_EVENT_USER_ADD** | ✅ Implemented | Full user/guild data |
| **GUILD_SCHEDULED_EVENT_USER_REMOVE** | ✅ Implemented | Full user/guild data |
| **AUTO_MODERATION_RULE_CREATE** | ✅ Implemented | Full rule entity |
| **AUTO_MODERATION_RULE_UPDATE** | ✅ Implemented | Full with change tracking |
| **AUTO_MODERATION_RULE_DELETE** | ✅ Implemented | Full rule entity |
| **AUTO_MODERATION_ACTION_EXECUTION** | ✅ Implemented | Full action context |
| **GUILD_AUDIT_LOG_ENTRY_CREATE** | ⚠️ Simplified | Basic event |
| **ENTITLEMENT_CREATE** | ⚠️ Simplified | Basic event |
| **ENTITLEMENT_UPDATE** | ⚠️ Simplified | Basic event |
| **ENTITLEMENT_DELETE** | ⚠️ Simplified | Basic event |

---

## Plugin System Status

| Feature | Status | Notes |
|---------|--------|-------|
| **Plugin Base Class** | ✅ Implemented | Lifecycle hooks, metadata |
| **Plugin Registry** | ✅ Implemented | Registration, dependencies |
| **Command DSL** | ✅ Implemented | Full command registration with options |
| **Event Registration** | ✅ Implemented | Through Plugin class |
| **Middleware Chain** | ✅ Implemented | Global and per-plugin middleware |
| **Analytics Plugin** | ✅ Implemented | Full metrics collection |
| **Logging Plugin** | 📝 Planned | Enhanced structured logging |
| **Monitoring Plugin** | 📝 Planned | Health checks, alerts |

---

## Infrastructure & DevOps

| Feature | Status | Notes |
|---------|--------|-------|
| **Docker Support** | ❌ Not Implemented | Dockerfile needed |
| **Kubernetes Operator** | ❌ Not Implemented | Planned for v1.0 |
| **Process Manager Integration** | ❌ Not Implemented | systemd, supervisor configs |
| **Graceful Shutdown** | 🔄 Partial | SIGTERM handling basic |
| **Signal Handling** | 🔄 Partial | Basic Interrupt handling |
| **Configuration Files** | ⚠️ Simplified | Ruby-only, no YAML/TOML |
| **Environment Variables** | ✅ Implemented | Full env var support |
| **Secrets Management** | ❌ Not Implemented | Vault integration planned |
| **Logging Formats** | ✅ Implemented | Simple and structured JSON |
| **Log Rotation** | ❌ Not Implemented | External tool needed |
| **Tracing (OpenTelemetry)** | ❌ Not Implemented | Planned |
| **Error Tracking (Sentry)** | ❌ Not Implemented | Planned |

---

## Documentation Status

| Document | Status | Coverage |
|----------|--------|----------|
| **README.md** | ✅ Complete | Quick start, features |
| **Getting Started Guide** | ✅ Complete | Installation, basics |
| **Architecture Guide** | ✅ Complete | Component overview |
| **API Reference** | ❌ Not Generated | YARD docs needed |
| **Examples** | ✅ Complete | 7 working examples |
| **This Roadmap** | ✅ Complete | Full status tracking |
| **Contributing Guide** | 📝 Planned | |
| **Changelog** | 📝 Planned | |
| **Migration Guide** | 📝 Planned | From other libraries |

---

## Known Issues & Limitations

### Critical
1. **Voice Gateway** - Not implemented, bots cannot join voice channels
2. **Interaction Response** - Basic support only, no full command system
3. **File Uploads** - ✅ Implemented | Multipart/form-data with proper handling |
4. **Pagination** - ✅ Implemented | Automatic pagination for list endpoints |

### Important
1. **Hot Reload** - Uses polling instead of file system events
2. **Queue Processing** - Needs better async integration with Async gem
3. **Error Recovery** - Some edge cases in reconnection not handled
4. **Cache Invalidation** - Not comprehensive across all event types

### Minor
1. **Embed Limits** - No validation of Discord's embed limits
2. **Message Content Intent** - No automatic handling of intent requirements
3. **Gateway Compression** - zlib-stream works but could be optimized
4. **Rate Limit Precision** - Uses polling loop instead of exact timers

---

## Version Planning

### v0.1.0 (Current - Alpha)
- ✅ Core bot functionality
- ✅ Scalable REST architecture
- ✅ Basic entity support
- ✅ Plugin system foundation

### v0.2.0 (Beta - Next)
- 📝 Full REST API coverage
- 📝 Slash command system
- 📝 Voice gateway
- 📝 File uploads
- 📝 Comprehensive tests

### v0.3.0 (Release Candidate)
- 📝 Performance optimizations
- 📝 Production hardening
- 📝 Full documentation
- 📝 Migration guides

### v1.0.0 (Stable)
- 📝 Stable API guarantee
- 📝 Enterprise features
- 📝 Advanced monitoring
- 📝 Kubernetes support

---

## How to Contribute

To help implement missing features:

1. Pick a feature from the "Not Implemented" list
2. Create a new file in appropriate directory
3. Follow existing patterns (factory, immutable entities)
4. Add comprehensive YARD documentation
5. Write tests in `spec/`
6. Update this roadmap

Priority areas:
- Voice Gateway support
- Slash command system
- File upload handling
- Pagination helpers

---

## Summary Statistics

| Category | Implemented | Partial | Not Implemented | Total |
|----------|-------------|---------|-----------------|-------|
| **Core Scalability** | 12 | 8 | 2 | 22 |
| **Gateway Features** | 9 | 0 | 1 | 10 |
| **REST - Channels** | 5 | 9 | 29 | 43 |
| **REST - Guilds** | 3 | 15 | 34 | 52 |
| **REST - Interactions** | 0 | 1 | 22 | 23 |
| **REST - Users** | 2 | 1 | 7 | 10 |
| **REST - Webhooks** | 0 | 5 | 10 | 15 |
| **REST - Other** | 2 | 0 | 9 | 11 |
| **Entities** | 5 | 5 | 4 | 14 |
| **Events** | 7 | 38 | 0 | 45 |
| **Plugins** | 3 | 2 | 2 | 7 |
| **Infrastructure** | 2 | 2 | 6 | 10 |
| **Documentation** | 4 | 0 | 1 | 5 |

**Total Discord API v10 Coverage**: ~45%
**Core Stability**: Alpha (improved)
**Production Ready**: No - wait for v0.3.0+

---

**Last Updated**: 2026-03-30
