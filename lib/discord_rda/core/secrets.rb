# frozen_string_literal: true

require 'json'
require 'yaml'

module DiscordRDA
  class Secrets
    def self.fetch(key, default: nil, required: false)
      value = ENV[key.to_s]
      if required && (value.nil? || value.empty?)
        raise KeyError, "Missing required secret: #{key}"
      end

      value.nil? || value.empty? ? default : value
    end

    def self.load_file(path)
      content = File.read(path)

      case File.extname(path).downcase
      when '.json'
        JSON.parse(content)
      when '.yml', '.yaml'
        YAML.safe_load(content, aliases: true) || {}
      else
        raise ArgumentError, "Unsupported secrets file format: #{path}"
      end
    end
  end
end
