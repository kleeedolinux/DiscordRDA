# frozen_string_literal: true

module DiscordRDA
  class ErrorTracker
    attr_reader :enabled

    def initialize(enabled: false, logger: nil)
      @enabled = enabled
      @logger = logger
    end

    def capture(error, **context)
      return unless enabled

      if defined?(::Sentry)
        ::Sentry.capture_exception(error, extra: context)
      else
        @logger&.error('Captured error', error: error, **context)
      end
    end
  end
end
