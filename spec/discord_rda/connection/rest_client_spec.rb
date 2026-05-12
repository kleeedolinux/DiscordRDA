# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe DiscordRDA::RestClient do
  subject(:client) { described_class.new(config, nil) }

  let(:config) { instance_double(DiscordRDA::Configuration, token: 'token') }

  describe '#handle_response' do
    let(:status) { 200 }
    let(:body) { '' }
    let(:response) { instance_double('response', status: status, read: body) }

    it 'returns nil for successful empty responses' do
      allow(response).to receive(:status).and_return(204)

      expect(client.send(:handle_response, response)).to be_nil
    end

    it 'returns plain text when the response is not json' do
      allow(response).to receive(:read).and_return('ok')

      expect(client.send(:handle_response, response)).to eq('ok')
    end
  end
end
