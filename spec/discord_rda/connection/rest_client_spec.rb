# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe DiscordRDA::RestClient do
  subject(:client) { described_class.new(config, nil) }

  let(:config) { instance_double(DiscordRDA::Configuration, token: 'token') }

  describe '#handle_response' do
    let(:response) { instance_double('response', status: status, read: body) }

    it 'returns nil for successful empty responses' do
      status = 204
      body = ''

      expect(client.send(:handle_response, response)).to be_nil
    end

    it 'returns plain text when the response is not json' do
      status = 200
      body = 'ok'

      expect(client.send(:handle_response, response)).to eq('ok')
    end
  end
end
