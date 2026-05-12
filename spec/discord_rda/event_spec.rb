# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe DiscordRDA::EventFactory do
  describe '.create' do
    it 'creates a typed presence update event with rich accessors' do
      event = described_class.create(
        'PRESENCE_UPDATE',
        {
          'guild_id' => '123',
          'status' => 'online',
          'user' => { 'id' => '456', 'username' => 'Klee' },
          'activities' => [{ 'name' => 'Testing' }],
          'client_status' => { 'desktop' => 'online' }
        },
        2
      )

      expect(event).to be_a(DiscordRDA::PresenceUpdateEvent)
      expect(event.shard_id).to eq(2)
      expect(event.guild_id.to_s).to eq('123')
      expect(event.user.username).to eq('Klee')
      expect(event.status).to eq('online')
      expect(event.activities.first['name']).to eq('Testing')
      expect(event.client_status['desktop']).to eq('online')
    end

    it 'creates a typed voice state update event' do
      event = described_class.create(
        'VOICE_STATE_UPDATE',
        {
          'guild_id' => '123',
          'channel_id' => '789',
          'user_id' => '456',
          'session_id' => 'session-1',
          'member' => {
            'user' => { 'id' => '456', 'username' => 'Klee' },
            'roles' => [],
            'mute' => false,
            'deaf' => false
          }
        }
      )

      expect(event).to be_a(DiscordRDA::VoiceStateUpdateEvent)
      expect(event.voice_state.connected?).to be(true)
      expect(event.channel_id.to_s).to eq('789')
      expect(event.member.user.username).to eq('Klee')
      expect(event.session_id).to eq('session-1')
    end

    it 'creates typed stage instance and entitlement events' do
      stage_event = described_class.create(
        'STAGE_INSTANCE_CREATE',
        {
          'guild_id' => '123',
          'channel_id' => '456',
          'topic' => 'Town Hall',
          'privacy_level' => 2
        }
      )

      entitlement_event = described_class.create(
        'ENTITLEMENT_CREATE',
        {
          'id' => '999',
          'sku_id' => '111',
          'application_id' => '222',
          'user_id' => '333',
          'starts_at' => '2026-05-12T18:00:00Z',
          'ends_at' => '2026-05-13T18:00:00Z'
        }
      )

      expect(stage_event).to be_a(DiscordRDA::StageInstanceCreateEvent)
      expect(stage_event.stage_instance.guild_only?).to be(true)
      expect(stage_event.channel_id.to_s).to eq('456')

      expect(entitlement_event).to be_a(DiscordRDA::EntitlementCreateEvent)
      expect(entitlement_event.entitlement.active?(at: Time.utc(2026, 5, 12, 19, 0, 0))).to be(true)
      expect(entitlement_event.entitlement.owner_type).to eq(:user)
    end

    it 'allows registering custom event classes' do
      custom_class = Class.new(DiscordRDA::Event) do
        def initialize(data, shard_id:)
          super('CUSTOM_EVENT', data, shard_id: shard_id)
        end
      end

      stub_const('DiscordRDA::CustomEvent', custom_class)
      described_class.register('CUSTOM_EVENT', DiscordRDA::CustomEvent)

      event = described_class.create('CUSTOM_EVENT', { 'ok' => true }, 4)

      expect(event).to be_a(DiscordRDA::CustomEvent)
      expect(event.shard_id).to eq(4)
      expect(event.data['ok']).to be(true)
    end
  end
end
