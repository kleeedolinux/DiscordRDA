# frozen_string_literal: true

module DiscordRDA
  class Tracer
    Span = Struct.new(:name, :attributes, :started_at, :finished_at, :error, keyword_init: true)

    attr_reader :enabled

    def initialize(enabled: false, logger: nil)
      @enabled = enabled
      @logger = logger
    end

    def with_span(name, **attributes)
      return yield unless enabled

      span = Span.new(name: name, attributes: attributes, started_at: Time.now.utc)
      if defined?(::OpenTelemetry::Trace)
        tracer = ::OpenTelemetry.tracer_provider.tracer('discord_rda')
        tracer.in_span(name, attributes: attributes) { yield }
      else
        yield
      end
    rescue StandardError => e
      span.error = e
      raise
    ensure
      if enabled

        span.finished_at = Time.now.utc
        @logger&.debug(
          'Trace span',
          span: span.name,
          duration_ms: ((span.finished_at - span.started_at) * 1000).round(2),
          error: span.error&.class&.name,
          **span.attributes
        )
      end
    end
  end
end
