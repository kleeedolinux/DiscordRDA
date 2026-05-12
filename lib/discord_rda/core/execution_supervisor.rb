# frozen_string_literal: true

require 'json'
require 'rbconfig'
require 'tempfile'
require 'timeout'

module DiscordRDA
  class ExecutionSupervisor
    DEFAULT_POLICY = {
      timeout_seconds: 15,
      max_concurrency: 8,
      failure_threshold: 5,
      cooldown_seconds: 60
    }.freeze

    class TimeoutError < StandardError; end
    class ConcurrencyLimitError < StandardError; end
    class CircuitOpenError < StandardError; end
    class IsolatedExecutionError < StandardError; end

    attr_reader :logger

    def initialize(logger: nil)
      @logger = logger
      @states = {}
      @mutex = Mutex.new
    end

    def execute(key, policy: {}, &block)
      merged = DEFAULT_POLICY.merge(policy || {})
      state = state_for(key)

      raise CircuitOpenError, "Circuit open for #{key}" if circuit_open?(state)
      acquire_slot!(key, state, merged)

      begin
        result = ::Timeout.timeout(merged[:timeout_seconds]) { block.call }
        record_success(state)
        result
      rescue ::Timeout::Error => e
        record_failure(state)
        raise TimeoutError, e.message
      rescue StandardError
        record_failure(state)
        raise
      ensure
        release_slot(state)
      end
    end

    def run_isolated(ruby_code:, timeout_seconds: 15, memory_limit_mb: nil, env: {})
      Tempfile.create(['discord_rda_isolated', '.rb']) do |file|
        file.write(build_isolated_runner(ruby_code, memory_limit_mb))
        file.flush

        stdout, stderr, status = spawn_with_timeout(
          [RbConfig.ruby, file.path],
          timeout_seconds: timeout_seconds,
          env: env
        )

        raise IsolatedExecutionError, stderr unless status.success?

        stdout
      end
    end

    private

    def state_for(key)
      @mutex.synchronize do
        @states[key] ||= {
          running: 0,
          failures: 0,
          opened_at: nil,
          failure_threshold: DEFAULT_POLICY[:failure_threshold],
          cooldown_seconds: DEFAULT_POLICY[:cooldown_seconds]
        }
      end
    end

    def circuit_open?(state)
      @mutex.synchronize do
        return false unless state[:opened_at]

        if Time.now.to_f - state[:opened_at] >= state[:cooldown_seconds]
          state[:opened_at] = nil
          state[:failures] = 0
          false
        else
          true
        end
      end
    end

    def acquire_slot!(key, state, policy)
      @mutex.synchronize do
        state[:failure_threshold] = policy[:failure_threshold]
        state[:cooldown_seconds] = policy[:cooldown_seconds]

        if state[:running] >= policy[:max_concurrency]
          raise ConcurrencyLimitError, "Concurrency limit reached for #{key}"
        end

        state[:running] += 1
      end
    end

    def release_slot(state)
      @mutex.synchronize do
        state[:running] -= 1 if state[:running].positive?
      end
    end

    def record_success(state)
      @mutex.synchronize do
        state[:failures] = 0
        state[:opened_at] = nil
      end
    end

    def record_failure(state)
      @mutex.synchronize do
        state[:failures] += 1
        if state[:failures] >= state[:failure_threshold]
          state[:opened_at] = Time.now.to_f
        end
      end
    end

    def spawn_with_timeout(command, timeout_seconds:, env:)
      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe

      pid = Process.spawn(env, *command, out: stdout_w, err: stderr_w)
      stdout_w.close
      stderr_w.close

      timed_out = false
      begin
        ::Timeout.timeout(timeout_seconds) { Process.wait(pid) }
      rescue ::Timeout::Error
        timed_out = true
        Process.kill('KILL', pid) rescue nil
        Process.wait(pid) rescue nil
      end

      stdout = stdout_r.read
      stderr = stderr_r.read
      stdout_r.close
      stderr_r.close

      if timed_out
        raise TimeoutError, "Isolated execution timed out after #{timeout_seconds}s"
      end

      [stdout, stderr, $CHILD_STATUS]
    end

    def build_isolated_runner(ruby_code, memory_limit_mb)
      limit_code = if memory_limit_mb
        "Process.setrlimit(:AS, #{memory_limit_mb.to_i} * 1024 * 1024)\n"
      else
        ''
      end

      <<~RUBY
        # frozen_string_literal: true
        #{limit_code}begin
          #{ruby_code}
        rescue StandardError => e
          warn("#{e.class}: #{e.message}")
          warn(e.backtrace.join("\\n")) if e.backtrace
          exit(1)
        end
      RUBY
    end
  end
end
