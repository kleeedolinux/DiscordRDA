# frozen_string_literal: true

require_relative '../../spec_helper'
require 'discord_rda/core/snowflake'

RSpec.describe DiscordRDA::Snowflake do
  let(:snowflake_id) { '1234567890123456789' }
  let(:snowflake) { described_class.new(snowflake_id) }

  describe '#initialize' do
    it 'accepts string values' do
      s = described_class.new('1234567890123456789')
      expect(s.value).to eq(1234567890123456789)
    end

    it 'accepts integer values' do
      s = described_class.new(1234567890123456789)
      expect(s.value).to eq(1234567890123456789)
    end

    it 'is frozen' do
      expect(snowflake).to be_frozen
    end
  end

  describe '.generate' do
    it 'generates a valid snowflake' do
      s = described_class.generate
      expect(s).to be_a(described_class)
      expect(s.value).to be > 0
    end
  end

  describe '.parse' do
    it 'parses string values' do
      s = described_class.parse('1234567890123456789')
      expect(s.value).to eq(1234567890123456789)
    end
  end

  describe '#timestamp' do
    it 'extracts timestamp from snowflake' do
      expect(snowflake.timestamp).to be_a(Time)
    end

    it 'is UTC' do
      expect(snowflake.timestamp.utc?).to be true
    end
  end

  describe '#worker_id' do
    it 'extracts worker ID' do
      expect(snowflake.worker_id).to be_a(Integer)
      expect(snowflake.worker_id).to be >= 0
    end
  end

  describe '#process_id' do
    it 'extracts process ID' do
      expect(snowflake.process_id).to be_a(Integer)
      expect(snowflake.process_id).to be >= 0
    end
  end

  describe '#increment' do
    it 'extracts increment' do
      expect(snowflake.increment).to be_a(Integer)
      expect(snowflake.increment).to be >= 0
    end
  end

  describe '#to_i' do
    it 'returns integer value' do
      expect(snowflake.to_i).to eq(1234567890123456789)
    end
  end

  describe '#to_s' do
    it 'returns string value' do
      expect(snowflake.to_s).to eq('1234567890123456789')
    end
  end

  describe '#==' do
    it 'returns true for equal snowflakes' do
      s1 = described_class.new(1234567890123456789)
      s2 = described_class.new('1234567890123456789')
      expect(s1).to eq(s2)
    end

    it 'returns false for different snowflakes' do
      s1 = described_class.new(1234567890123456789)
      s2 = described_class.new(9876543210987654321)
      expect(s1).not_to eq(s2)
    end
  end

  describe '#<=>' do
    it 'compares by timestamp' do
      old = described_class.new(1000000000000000000)
      new = described_class.new(9000000000000000000)
      expect(old < new).to be true
    end
  end
end
