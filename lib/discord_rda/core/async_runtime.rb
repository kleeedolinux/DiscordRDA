# frozen_string_literal: true

require 'async'
require 'console'

module DiscordRDA
  # Wrapper around Ruby's Fiber scheduler for async operations.
  # Provides a simple interface for running concurrent tasks.
  #
  # @example Basic usage
  #   runtime = AsyncRuntime.new
  #   runtime.async { perform_io_operation }
  #   runtime.run
  #
  class AsyncRuntime
    # Initialize a new async runtime
    def initialize
      @tasks = []
    end

    # Schedule a task to run asynchronously
    # @yield The block to execute asynchronously
    # @return [Async::Task] The scheduled task
    def async(&block)
      task = Async(&block)
      @tasks << task
      task
    end

    # Run the event loop until all tasks complete
    # This is a blocking call
    # @return [void]
    def run
      # Handled by Async reactor automatically
    end

    # Run the event loop indefinitely
    # Used for long-running applications like bots
    # @return [void]
    def run_forever
      Async::Reactor.run do |task|
        task.yield
      end
    end

    # Stop all running tasks
    # @return [void]
    def stop
      @tasks.each(&:stop)
      @tasks.clear
    end

    # Create a timer that fires after a delay
    # @param delay [Float] Delay in seconds
    # @yield The block to execute after the delay
    # @return [Timers::Timer] The timer object
    def after(delay, &block)
      Async::Reactor.run do
        sleep(delay)
        block.call
      end
    end

    # Create a periodic timer
    # @param interval [Float] Interval in seconds
    # @yield The block to execute periodically
    # @return [void]
    def every(interval, &block)
      Async do
        loop do
          block.call
          sleep(interval)
        end
      end
    end

    class << self
      # Run a block within the async runtime
      # @yield The block to run
      # @return [void]
      def run(&block)
        Async(&block)
      end

      # Run multiple tasks concurrently and wait for all
      # @param tasks [Array<Proc>] Tasks to run
      # @return [Array] Results from all tasks
      def await_all(*tasks)
        Async do
          tasks.map do |task|
            Async { task.call }.wait
          end
        end.wait
      end

      # Run tasks concurrently and return first result
      # @param tasks [Array<Proc>] Tasks to run
      # @return [Object] First completed result
      def await_any(*tasks)
        Async do |parent_task|
          tasks.map do |task|
            parent_task.async { task.call }
          end.first.wait
        end.wait
      end
    end
  end
end
