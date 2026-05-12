# frozen_string_literal: true

require 'logger'
require 'json'
require 'fileutils'

module DiscordRDA
  # Structured logging for DiscordRDA.
  # Supports both simple and structured (JSON) log formats.
  #
  # @example Basic logging
  #   logger = Logger.new(log_level: :info)
  #   logger.info("Bot starting")
  #   logger.warn("Rate limit approaching", threshold: 0.8)
  #
  class Logger
    # Log levels
    LEVELS = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3,
      fatal: 4
    }.freeze

    # @return [Symbol] Current log level
    attr_reader :level

    # @return [Symbol] Log format (:simple or :structured)
    attr_reader :format

    # @return [IO] Output destination
    attr_reader :output

    # Create a new logger
    # @param level [Symbol] Log level
    # @param format [Symbol] Log format
    # @param output [IO] Output destination (default: STDOUT)
    def initialize(level: :info, format: :structured, output: STDOUT, file_path: nil, rotate_age: 7, rotate_size: 10_485_760)
      @level = level.to_sym
      @format = format.to_sym
      @output = build_output(output, file_path, rotate_age, rotate_size)
      @mutex = Mutex.new
    end

    # Log a debug message
    # @param message [String] Log message
    # @param context [Hash] Additional context
    def debug(message, **context)
      log(:debug, message, context)
    end

    # Log an info message
    # @param message [String] Log message
    # @param context [Hash] Additional context
    def info(message, **context)
      log(:info, message, context)
    end

    # Log a warning message
    # @param message [String] Log message
    # @param context [Hash] Additional context
    def warn(message, **context)
      log(:warn, message, context)
    end

    # Log an error message
    # @param message [String] Log message
    # @param error [Exception, nil] Optional error object
    # @param context [Hash] Additional context
    def error(message, error: nil, **context)
      context = context.dup
      context[:error_class] = error.class.name if error
      context[:error_message] = error.message if error
      context[:backtrace] = error.backtrace.first(5) if error&.backtrace
      log(:error, message, context)
    end

    # Log a fatal message
    # @param message [String] Log message
    # @param error [Exception, nil] Optional error object
    # @param context [Hash] Additional context
    def fatal(message, error: nil, **context)
      context = context.dup
      context[:error_class] = error.class.name if error
      context[:error_message] = error.message if error
      log(:fatal, message, context)
    end

    # Check if a level is enabled
    # @param level [Symbol] Level to check
    # @return [Boolean] True if enabled
    def level_enabled?(level)
      LEVELS[level.to_sym] >= LEVELS[@level]
    end

    # Create a child logger with additional context
    # @param context [Hash] Context to add to all logs
    # @return [ContextualLogger] Child logger
    def with_context(**context)
      ContextualLogger.new(self, context)
    end

    private

    def build_output(output, file_path, rotate_age, rotate_size)
      return output unless file_path

      FileUtils.mkdir_p(File.dirname(file_path))
      ::Logger::LogDevice.new(file_path, shift_age: rotate_age, shift_size: rotate_size)
    end

    def log(level, message, context)
      return unless level_enabled?(level)

      entry = build_log_entry(level, message, context)
      @mutex.synchronize do
        if @output.respond_to?(:puts)
          @output.puts(entry)
        else
          @output.write("#{entry}\n")
        end
      end
    end

    def build_log_entry(level, message, context)
      timestamp = Time.now.utc.iso8601(3)

      case @format
      when :structured
        build_structured_entry(timestamp, level, message, context)
      else
        build_simple_entry(timestamp, level, message, context)
      end
    end

    def build_structured_entry(timestamp, level, message, context)
      entry = {
        timestamp: timestamp,
        level: level.to_s.upcase,
        message: message,
        library: 'DiscordRDA'
      }
      entry.merge!(context) if context.any?
      JSON.generate(entry)
    end

    def build_simple_entry(timestamp, level, message, context)
      base = "[#{timestamp}] #{level.to_s.upcase}: #{message}"
      return base if context.empty?

      context_str = context.map { |k, v| "#{k}=#{format_value(v)}" }.join(' ')
      "#{base} | #{context_str}"
    end

    def format_value(value)
      case value
      when Hash then value.to_json
      when Array then value.join(',')
      else value.to_s
      end
    end

    # Logger with predefined context
    class ContextualLogger
      def initialize(parent, context)
        @parent = parent
        @context = context.freeze
      end

      def debug(message, **context)
        @parent.debug(message, **merge_context(context))
      end

      def info(message, **context)
        @parent.info(message, **merge_context(context))
      end

      def warn(message, **context)
        @parent.warn(message, **merge_context(context))
      end

      def error(message, error: nil, **context)
        @parent.error(message, error: error, **merge_context(context))
      end

      def fatal(message, error: nil, **context)
        @parent.fatal(message, error: error, **merge_context(context))
      end

      def with_context(**additional_context)
        ContextualLogger.new(@parent, @context.merge(additional_context))
      end

      private

      def merge_context(context)
        @context.merge(context)
      end
    end
  end
end
