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
          issues: detect_issues,
          checks: run_health_checks
        },
        system: system_metrics
      }
    end

    def prometheus_export
      data = summary

      [
        '# HELP discord_rda_uptime_seconds Process uptime in seconds',
        '# TYPE discord_rda_uptime_seconds gauge',
        "discord_rda_uptime_seconds #{data[:uptime]}",
        '# HELP discord_rda_gateway_events_per_minute Gateway events per minute',
        '# TYPE discord_rda_gateway_events_per_minute gauge',
        "discord_rda_gateway_events_per_minute #{data[:gateway][:events_per_minute]}",
        '# HELP discord_rda_rest_requests_per_minute REST requests per minute',
        '# TYPE discord_rda_rest_requests_per_minute gauge',
        "discord_rda_rest_requests_per_minute #{data[:rest][:requests_per_minute]}",
        '# HELP discord_rda_cache_hit_rate Cache hit rate percentage',
        '# TYPE discord_rda_cache_hit_rate gauge',
        "discord_rda_cache_hit_rate #{data[:cache][:hit_rate]}",
        '# HELP discord_rda_shards_total_guilds Guilds across shards',
        '# TYPE discord_rda_shards_total_guilds gauge',
        "discord_rda_shards_total_guilds #{data[:shards][:total_guilds]}"
      ].join("\n") + "\n"
    end

    def grafana_dashboard(title: 'DiscordRDA Overview')
      dashboard = {
        title: title,
        schemaVersion: 39,
        version: 1,
        editable: true,
        panels: [
          metric_panel(id: 1, title: 'Gateway Events / Min', expr: 'discord_rda_gateway_events_per_minute'),
          metric_panel(id: 2, title: 'REST Requests / Min', expr: 'discord_rda_rest_requests_per_minute'),
          metric_panel(id: 3, title: 'Cache Hit Rate', expr: 'discord_rda_cache_hit_rate'),
          metric_panel(id: 4, title: 'Guilds', expr: 'discord_rda_shards_total_guilds')
        ]
      }

      Oj.dump(dashboard, mode: :compat)
    end

    # Run comprehensive health checks
    # @return [Hash] Health check results
    def run_health_checks
      checks = {}

      # Gateway health
      checks[:gateway] = check_gateway_health

      # REST API health
      checks[:rest] = check_rest_health

      # Cache health
      checks[:cache] = check_cache_health

      # Rate limiter health
      checks[:rate_limiter] = check_rate_limiter_health

      # Overall status
      all_healthy = checks.values.all? { |c| c[:status] == :healthy }
      checks[:overall] = {
        status: all_healthy ? :healthy : :degraded,
        timestamp: Time.now.utc.iso8601
      }

      checks
    end

    # Check gateway health
    # @return [Hash] Gateway health status
    def check_gateway_health
      reconnects_5min = get_metric(:gateway, :reconnects, window: 300)
      events_per_sec = get_metric(:gateway, :events_received, window: 1)

      status = if reconnects_5min > 10
        :critical
      elsif reconnects_5min > 5
        :warning
      elsif events_per_sec == 0 && uptime_seconds > 60
        :warning
      else
        :healthy
      end

      {
        status: status,
        reconnects_5min: reconnects_5min,
        events_per_sec: events_per_sec,
        connected: @bot&.shard_manager&.shards&.all?(&:connected?) || false
      }
    end

    # Check REST API health
    # @return [Hash] REST health status
    def check_rest_health
      rate_limited_1min = get_metric(:rest, :rate_limited, window: 60)
      errors_1min = get_metric(:rest, :errors, window: 60)
      avg_response = get_average(:rest, :avg_response_time, window: 60)

      status = if errors_1min > 10
        :critical
      elsif rate_limited_1min > 5 || errors_1min > 3
        :warning
      elsif avg_response > 5000
        :warning
      else
        :healthy
      end

      {
        status: status,
        rate_limited_1min: rate_limited_1min,
        errors_1min: errors_1min,
        avg_response_ms: avg_response.round(2)
      }
    end

    # Check cache health
    # @return [Hash] Cache health status
    def check_cache_health
      return { status: :unknown, reason: 'No cache configured' } unless @bot&.cache

      stats = @bot.cache.stats
      hit_rate = calculate_cache_hit_rate(window: 300)

      status = if hit_rate < 10 && stats[:size].to_i > 100
        :warning
      else
        :healthy
      end

      {
        status: status,
        hit_rate: hit_rate,
        size: stats[:size],
        memory_usage: stats[:memory_usage]
      }
    end

    # Check rate limiter health
    # @return [Hash] Rate limiter health status
    def check_rate_limiter_health
      return { status: :unknown } unless @bot&.rest.respond_to?(:rate_limiter)

      rl_status = @bot.rest.rate_limiter.status

      status = if rl_status[:global_limited]
        :warning
      else
        :healthy
      end

      {
        status: status,
        global_limited: rl_status[:global_limited],
        routes_tracked: rl_status[:routes_tracked]
      }
    end

    # Get system metrics
    # @return [Hash] System metrics
    def system_metrics
      {
        uptime: uptime_seconds,
        memory: memory_usage,
        cpu: cpu_usage,
        timestamp: Time.now.utc.iso8601
      }
    end

    def metric_panel(id:, title:, expr:)
      {
        id: id,
        type: 'stat',
        title: title,
        datasource: { type: 'prometheus', uid: '${DS_PROMETHEUS}' },
        targets: [{ expr: expr, refId: "A#{id}" }],
        gridPos: { h: 8, w: 12, x: ((id - 1) % 2) * 12, y: ((id - 1) / 2) * 8 }
      }
    end

    # Get memory usage
    # @return [Hash] Memory usage info
    def memory_usage
      # Try to get memory info from GC
      {
        gc_stat: GC.stat,
        total_objects: ObjectSpace.count_objects[:TOTAL]
      }
    rescue
      { error: 'Unable to retrieve' }
    end

    # Get process CPU usage
    # @return [Hash] CPU usage info
    def cpu_usage
      process_times = Process.times
      elapsed = uptime_seconds
      total_cpu_seconds = process_times.utime + process_times.stime
      cpu_percent = elapsed.positive? ? ((total_cpu_seconds / elapsed) * 100.0).round(2) : 0.0

      {
        available: true,
        user_seconds: process_times.utime.round(4),
        system_seconds: process_times.stime.round(4),
        total_seconds: total_cpu_seconds.round(4),
        utilization_percent: cpu_percent
      }
    rescue StandardError
      { available: false }
    end

    # Generate health check report
    # @return [String] Formatted health report
    def health_report
      checks = run_health_checks
      lines = [
        '🏥 DiscordRDA Health Report',
        '=' * 40,
        "Overall: #{emoji_for_status(checks[:overall][:status])} #{checks[:overall][:status].upcase}",
        "Timestamp: #{checks[:overall][:timestamp]}",
        '',
        '📡 Gateway:',
        "  Status: #{emoji_for_status(checks[:gateway][:status])} #{checks[:gateway][:status]}",
        "  Connected: #{checks[:gateway][:connected]}",
        "  Events/sec: #{checks[:gateway][:events_per_sec]}",
        '',
        '🌐 REST API:',
        "  Status: #{emoji_for_status(checks[:rest][:status])} #{checks[:rest][:status]}",
        "  Rate limited (1m): #{checks[:rest][:rate_limited_1min]}",
        "  Errors (1m): #{checks[:rest][:errors_1min]}",
        "  Avg response: #{checks[:rest][:avg_response_ms]}ms",
        '',
        '💾 Cache:',
        "  Status: #{emoji_for_status(checks[:cache][:status])} #{checks[:cache][:status]}",
        "  Hit rate: #{checks[:cache][:hit_rate]}%"
      ]

      lines.join("\n")
    end

    private

    def emoji_for_status(status)
      case status
      when :healthy then '✅'
      when :warning then '⚠️'
      when :critical then '❌'
      when :degraded then '🔶'
      else '❓'
      end
    end

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
