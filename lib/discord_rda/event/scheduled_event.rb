# frozen_string_literal: true

module DiscordRDA
  # Events for scheduled events (Discord's event/guild event feature)
  #
  class GuildScheduledEventCreateEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_SCHEDULED_EVENT_CREATE', data, shard_id: shard_id)
    end

    def event
      @event ||= GuildScheduledEvent.new(@data)
    end

    def guild_id
      @data['guild_id']
    end

    def channel_id
      @data['channel_id']
    end

    def creator_id
      @data['creator_id']
    end

    def name
      @data['name']
    end

    def description
      @data['description']
    end

    def scheduled_start_time
      @data['scheduled_start_time']
    end

    def scheduled_end_time
      @data['scheduled_end_time']
    end

    def privacy_level
      @data['privacy_level']
    end

    def status
      @data['status']
    end

    def entity_type
      @data['entity_type']
    end

    def entity_id
      @data['entity_id']
    end

    def entity_metadata
      @data['entity_metadata']
    end

    def creator
      @creator ||= User.new(@data['creator']) if @data['creator']
    end

    def user_count
      @data['user_count']
    end

    def image
      @data['image']
    end
  end

  class GuildScheduledEventUpdateEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_SCHEDULED_EVENT_UPDATE', data, shard_id: shard_id)
    end

    def event
      @event ||= GuildScheduledEvent.new(@data)
    end

    def guild_id
      @data['guild_id']
    end

    def channel_id
      @data['channel_id']
    end

    def status
      @data['status']
    end

    def status_changed?
      true
    end

    def cancelled?
      status == 4
    end

    def completed?
      status == 3
    end

    def active?
      status == 2
    end

    def scheduled?
      status == 1
    end
  end

  class GuildScheduledEventDeleteEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_SCHEDULED_EVENT_DELETE', data, shard_id: shard_id)
    end

    def event
      @event ||= GuildScheduledEvent.new(@data)
    end

    def event_id
      @data['id']
    end

    def guild_id
      @data['guild_id']
    end

    def name
      @data['name']
    end
  end

  class GuildScheduledEventUserAddEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_SCHEDULED_EVENT_USER_ADD', data, shard_id: shard_id)
    end

    def guild_scheduled_event_id
      @data['guild_scheduled_event_id']
    end

    def user_id
      @data['user_id']
    end

    def guild_id
      @data['guild_id']
    end
  end

  class GuildScheduledEventUserRemoveEvent < Event
    def initialize(data, shard_id:)
      super('GUILD_SCHEDULED_EVENT_USER_REMOVE', data, shard_id: shard_id)
    end

    def guild_scheduled_event_id
      @data['guild_scheduled_event_id']
    end

    def user_id
      @data['user_id']
    end

    def guild_id
      @data['guild_id']
    end
  end

  # Represents a scheduled event entity
  class GuildScheduledEvent < Entity
    # Privacy levels
    PRIVACY_LEVELS = {
      guild_only: 2
    }.freeze

    # Entity types
    ENTITY_TYPES = {
      stage_instance: 1,
      voice: 2,
      external: 3
    }.freeze

    # Statuses
    STATUSES = {
      scheduled: 1,
      active: 2,
      completed: 3,
      cancelled: 4
    }.freeze

    attribute :guild_id, type: :snowflake
    attribute :channel_id, type: :snowflake
    attribute :creator_id, type: :snowflake
    attribute :name, type: :string
    attribute :description, type: :string
    attribute :scheduled_start_time, type: :time
    attribute :scheduled_end_time, type: :time
    attribute :privacy_level, type: :integer
    attribute :status, type: :integer
    attribute :entity_type, type: :integer
    attribute :entity_id, type: :snowflake
    attribute :entity_metadata, type: :hash
    attribute :user_count, type: :integer
    attribute :image, type: :string

    def creator
      @creator ||= User.new(@raw_data['creator']) if @raw_data['creator']
    end

    def entity_type_name
      ENTITY_TYPES.key(entity_type) || :unknown
    end

    def status_name
      STATUSES.key(status) || :unknown
    end

    def scheduled?
      status == 1
    end

    def active?
      status == 2
    end

    def completed?
      status == 3
    end

    def cancelled?
      status == 4
    end

    def stage_instance?
      entity_type == 1
    end

    def voice?
      entity_type == 2
    end

    def external?
      entity_type == 3
    end

    def location
      entity_metadata&.dig('location')
    end
  end
end
