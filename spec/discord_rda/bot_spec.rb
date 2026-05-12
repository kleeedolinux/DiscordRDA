# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe DiscordRDA::Bot do
  describe '#context_menu' do
    let(:bot) { described_class.new(token: 'token') }
    let(:me) { instance_double(DiscordRDA::User, id: DiscordRDA::Snowflake.new('123456789012345678')) }

    before do
      allow(bot).to receive(:me).and_return(me)
    end

    it 'registers a user command instead of a slash command' do
      command = bot.context_menu(type: :user, name: 'Inspect') { |_interaction| nil }

      expect(command.type).to eq(2)
      expect(command.user_command?).to be(true)
      expect(command.description).to eq('')
    end
  end

  describe 'entity api wiring' do
    it 'assigns the rest client to entity helpers' do
      bot = described_class.new(token: 'token')

      expect(DiscordRDA::Message.api).to be(bot.rest)
      expect(DiscordRDA::Interaction.api).to be(bot.rest)
      expect(DiscordRDA::User.api).to be(bot.rest)
      expect(DiscordRDA::Guild.api).to be(bot.rest)
      expect(DiscordRDA::Channel.api).to be(bot.rest)
    end
  end
end
