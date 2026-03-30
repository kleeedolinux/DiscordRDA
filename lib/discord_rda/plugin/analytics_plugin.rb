# frozen_string_literal: true

module DiscordRDA
  # Analytics plugin for tracking bot metrics.
  # Provides beautiful analytics as inspired by Discordeno.
  #
  class AnalyticsPlugin < Plugin
    # @return [Hash] Metrics storage
    attr_reader :metrics

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [Integer] Metrics retention period (seconds)
    attr_reader :retention

    # Metrics categories
    CATEGORIES = {
      gateway: [:events_received, :events_sent, :heartbeat_acks, :reconnects],
      rest: [:requests_made, :rate_limited, :errors, :avg_response_time],
      cache: [:hits, :misses, :evictions, :size],
      shards: [:guilds, :members, :channels, :messages_per_minute]
    }.freeze

    # Initialize analytics plugin
    # @param retention [Integer] Metrics retention in seconds (default: 1 hour)
    # @param logger [Logger] Logger instance
    def initialize(retention: 3600, logger: nil)
      super(
        name: 'Analytics',
        version: '1.0.0',
        description: 'Track bot performance metrics'
      )

      @metrics = {}
      @logger = logger
      @retention = retention
      @start_time = Time.now.utc
      @mutex = Mutex.new

      initialize_metrics
    end

    # Setup analytics on bot
    # @param bot [Bot] Bot instance
    # @return [void]
    def setup(bot)
      @bot = bot
      setup_event_tracking(bot)
      setup_rest_tracking(bot)
      setup_cache_tracking(bot)
    end

    # Called when bot is ready
    # @param bot [Bot] Bot instance
    # @return [void]
    def ready(bot)
      @logger&.info('Analytics plugin ready')
      start_metrics_collection
    end

    # Record a metric
    # @param category [Symbol] Metric category
    # @param metric [Symbol] Metric name
    # @param value [Numeric] Metric value
    # @return [void]
    def record(category, metric, value = 1)
      return unless valid_metric?(category, metric)

      @mutex.synchronize do
        key = "#{category}:#{metric}"
        timestamp = Time.now.utc.to_i

        @metrics[key] ||= []
        @metrics[key] << { timestamp: timestamp, value: value }

        # Clean old data
        clean_old_data(key)
      end
    end

    # Get metric value (sum in time window)
    # @param category [Symbol] Metric category
    # @param metric [Symbol] Metric name
    # @param window [Integer] Time window in seconds
    # @return [Numeric] Sum of metric values
    def get_metric(category, metric, window: 60)
      key = "#{category}:#{metric}"
      cutoff = Time.now.utc.to_i - window

      @mutex.synchronize do
        data = @metrics[key] || []
        data.select { |d| d[:timestamp] >= cutoff }.sum { |d| d[:value] }
      end
    end

    # Get average metric value
    # @param category [Symbol] Metric category
    # @param metric [Symbol] Metric name
    # @param window [Integer] Time window in seconds
    # @return [Float] Average value
    def get_average(category, metric, window: 60)
      key = "#{category}:#{metric}"
      cutoff = Time.now.utc.to_i - window

      @mutex.synchronize do
        data = @metrics[key] || []
        recent = data.select { |d| d[:timestamp] >= cutoff }
        return 0.0 if recent.empty?

        recent.sum { |d| d[:value] }.to_f / recent.length
      end
    end

    # Get all metrics summary
    # @return [Hash] Metrics summary
    def summary
      @mutex.synchronize do
        {
          uptime: uptime_seconds,
          gateway: gateway_metrics,
          rest: rest_metrics,
          cache: cache_metrics,
          shards: shard_metrics
        }
      end
    end

    # Generate pretty formatted report
    # @return [String] Formatted report
    def pretty_report
      data = summary

      lines = [
        "📊 DiscordRDA Analytics Report",
        "=" * 40,
        "⏱️  Uptime: #{format_duration(data[:uptime])}",
        "",
        "📡 Gateway:",
        "  Events/min: #{data[:gateway][:events_per_minute]}",
        "  Reconnects: #{data[:gateway][:reconnects]}",
        "",
        "🌐 REST API:",
        "  Requests/min: #{data[:rest][:requests_per_minute]}",
        "  Avg Response: #{data[:rest][:avg_response_time]}ms",
        "  Rate Limited: #{data[:rest][:rate_limited]}",
        "",
        "💾 Cache:",
        "  Hit Rate: #{data[:cache][:hit_rate]}%",
        "  Size: #{data[:cache][:size]}",
        "",
        "🗂️  Shards:",
        "  Guilds: #{data[:shards][:total_guilds]}",
        "  Members: #{data[:shards][:total_members]}",
        "  Msg/min: #{data[:shards][:messages_per_minute]}"
      ]

      lines.join("\n")
    end

    # Export metrics to JSON
    # @return [String] JSON string
    def to_json
      Oj.dump(summary, mode: :compat)
    end

    # Get real-time dashboard data
    # @return [Hash] Dashboard data
    def dashboard_data
      {
        realtime: {
          events_per_second: get_metric(:gateway, :events_received, window: 1),
          requests_per_second: get_metric(:rest, :requests_made, window: 1),
          cache_hit_rate: calculate_cache_hit_rate(window: 60)
        },
        health: {
          status: health_status,
          issues: detect_issues
        }
      }
    end

    private

    def initialize_metrics
      CATEGORIES.each do |category, metrics|
        metrics.each do |metric|
          @metrics["#{category}:#{metric}"] = []
        end
      end
    end

    def setup_event_tracking(bot)
      bot.event_bus.on(:dispatch) do |event|
        record(:gateway, :events_received)
      end
    end

    def setup_rest_tracking(bot)
      # Hook into REST client if available
      if bot.respond_to?(:rest)
        # This would ideally hook into the REST client's request/response cycle
      end
    end

    def setup_cache_tracking(bot)
      # Hook into cache if available
      if bot.respond_to?(:cache)
        # Track cache hits/misses
      end
    end

    def start_metrics_collection
      # Start background collection thread
      Async do
        loop do
          sleep(60)
          collect_periodic_metrics
        end
      end
    end

    def collect_periodic_metrics
      return unless @bot

      # Collect shard metrics
      if @bot.respond_to?(:shard_manager)
        status = @bot.shard_manager.status
        record(:shards, :guilds, status[:guilds] || 0)
      end

      # Collect cache metrics
      if @bot.respond_to?(:cache)
        stats = @bot.cache.stats
        record(:cache, :size, stats[:size] || 0)
      end
    end

    def clean_old_data(key)
      cutoff = Time.now.utc.to_i - @retention
      @metrics[key].delete_if { |d| d[:timestamp] < cutoff }
    end

    def valid_metric?(category, metric)
      CATEGORIES[category]&.include?(metric)
    end

    def uptime_seconds
      (Time.now.utc - @start_time).to_i
    end

    def gateway_metrics
      {
        events_per_minute: get_metric(:gateway, :events_received, window: 60),
        reconnects: get_metric(:gateway, :reconnects, window: 3600)
      }
    end

    def rest_metrics
      {
        requests_per_minute: get_metric(:rest, :requests_made, window: 60),
        rate_limited: get_metric(:rest, :rate_limited, window: 3600),
        avg_response_time: get_average(:rest, :avg_response_time, window: 60).round(2)
      }
    end

    def cache_metrics
      hits = get_metric(:cache, :hits, window: 60)
      misses = get_metric(:cache, :misses, window: 60)
      total = hits + misses

      {
        hit_rate: total > 0 ? ((hits.to_f / total) * 100).round(1) : 0,
        size: get_metric(:cache, :size, window: 1)
      }
    end

    def shard_metrics
      {
        total_guilds: get_metric(:shards, :guilds, window: 60),
        total_members: get_metric(:shards, :members, window: 60),
        messages_per_minute: get_metric(:shards, :messages_per_minute, window: 60)
      }
    end

    def calculate_cache_hit_rate(window:)
      hits = get_metric(:cache, :hits, window: window)
      misses = get_metric(:cache, :misses, window: window)
      total = hits + misses

      total > 0 ? ((hits.to_f / total) * 100).round(1) : 0
    end

    def health_status
      issues = detect_issues

      if issues.empty?
        :healthy
      elsif issues.length < 3
        :warning
      else
        :critical
      end
    end

    def detect_issues
      issues = []

      # Check rate limiting
      if get_metric(:rest, :rate_limited, window: 60) > 10
        issues << "High rate limiting"
      end

      # Check errors
      if get_metric(:rest, :errors, window: 60) > 5
        issues << "High error rate"
      end

      # Check reconnects
      if get_metric(:gateway, :reconnects, window: 300) > 5
        issues << "Frequent reconnects"
      end

      issues
    end

    def format_duration(seconds)
      if seconds < 60
        "#{seconds}s"
      elsif seconds < 3600
        "#{(seconds / 60).round}m"
      elsif seconds < 86400
        "#{(seconds / 3600).round}h"
      else
        "#{(seconds / 86400).round}d"
      end
    end
  end
end
