# frozen_string_literal: true

module DiscordRDA
  # Event bus for publish-subscribe event handling.
  # Routes events from Gateway to registered handlers.
  #
  class EventBus
    # @return [Hash<String, Array<EventHandler>>] Registered handlers
    attr_reader :handlers

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [Array<Middleware>] Global middleware
    attr_reader :middleware

    # Initialize event bus
    # @param logger [Logger] Logger instance
    def initialize(logger: nil)
      @logger = logger
      @handlers = {}
      @middleware = []
      @mutex = Mutex.new
    end

    # Subscribe to an event type
    # @param event_type [String, Symbol] Event type to subscribe to
    # @param handler [Proc, EventHandler] Handler to call
    # @param middleware [Array<Middleware>] Middleware for this subscription
    # @yield Block to execute for event
    # @return [Subscription] Subscription object
    def on(event_type, handler = nil, middleware: [], &block)
      handler = block if block_given?
      handler = EventHandler.new(handler) unless handler.is_a?(EventHandler)

      event_type = normalize_event_type(event_type)

      @mutex.synchronize do
        @handlers[event_type] ||= []
        @handlers[event_type] << { handler: handler, middleware: middleware }
      end

      @logger&.debug('Registered handler', event: event_type)

      Subscription.new(self, event_type, handler)
    end

    # Subscribe to an event once
    # @param event_type [String, Symbol] Event type
    # @param handler [Proc, EventHandler] Handler
    # @yield Block to execute
    # @return [Subscription] Subscription object
    def once(event_type, handler = nil, &block)
      handler = block if block_given?
      wrapped_handler = proc do |event|
        handler.call(event)
        :unsubscribe
      end

      on(event_type, wrapped_handler)
    end

    # Publish an event to all subscribers
    # @param event_type [String, Symbol] Event type
    # @param event [Event] Event object
    # @return [void]
    def publish(event_type, event)
      event_type = normalize_event_type(event_type)
      subscriptions = @mutex.synchronize { @handlers[event_type]&.dup || [] }

      return if subscriptions.empty?

      @logger&.debug('Publishing event', type: event_type, handler_count: subscriptions.length)

      subscriptions.each do |sub|
        dispatch_with_middleware(sub[:handler], event, sub[:middleware])
      end
    end

    # Unsubscribe a handler
    # @param event_type [String, Symbol] Event type
    # @param handler [EventHandler] Handler to remove
    # @return [void]
    def off(event_type, handler)
      event_type = normalize_event_type(event_type)

      @mutex.synchronize do
        @handlers[event_type]&.reject! { |sub| sub[:handler] == handler }
      end

      @logger&.debug('Unregistered handler', event: event_type)
    end

    # Add global middleware
    # @param middleware [Middleware] Middleware to add
    # @return [void]
    def use(middleware)
      @middleware << middleware
    end

    # Remove global middleware
    # @param middleware [Middleware] Middleware to remove
    # @return [void]
    def unuse(middleware)
      @middleware.delete(middleware)
    end

    # Get all registered event types
    # @return [Array<String>] Event types
    def event_types
      @handlers.keys
    end

    # Check if event type has handlers
    # @param event_type [String, Symbol] Event type
    # @return [Boolean] True if has handlers
    def has_handlers?(event_type)
      event_type = normalize_event_type(event_type)
      @handlers[event_type]&.any?
    end

    # Wait for an event (async)
    # @param event_type [String, Symbol] Event type to wait for
    # @param timeout [Float] Timeout in seconds
    # @yield Block to match event
    # @return [Event, nil] Event or nil if timeout
    def wait_for(event_type, timeout: nil, &block)
      Async::Condition.new.tap do |condition|
        handler = on(event_type) do |event|
          if block.nil? || block.call(event)
            condition.signal(event)
            :unsubscribe
          end
        end

        timer = Async do
          sleep(timeout) if timeout
          condition.signal(nil)
        end if timeout

        result = condition.wait
        timer&.stop
        result
      end
    end

    private

    def normalize_event_type(event_type)
      event_type.to_s.upcase
    end

    def dispatch_with_middleware(handler, event, middleware)
      # Build middleware chain
      chain = @middleware + middleware

      if chain.empty?
        execute_handler(handler, event)
      else
        execute_with_chain(chain, handler, event)
      end
    end

    def execute_with_chain(chain, handler, event)
      index = 0

      call_next = proc do
        if index < chain.length
          middleware = chain[index]
          index += 1
          middleware.call(event, &call_next)
        else
          execute_handler(handler, event)
        end
      end

      call_next.call
    end

    def execute_handler(handler, event)
      result = handler.call(event)
      :unsubscribe if result == :unsubscribe
    rescue => e
      @logger&.error('Event handler error', event: event.class.name, error: e)
      nil
    end

    # Subscription object for managing handler lifecycle
    class Subscription
      # @return [EventBus] Event bus
      attr_reader :bus

      # @return [String] Event type
      attr_reader :event_type

      # @return [EventHandler] Handler
      attr_reader :handler

      # @return [Boolean] Whether active
      attr_reader :active

      def initialize(bus, event_type, handler)
        @bus = bus
        @event_type = event_type
        @handler = handler
        @active = true
      end

      # Unsubscribe this handler
      # @return [void]
      def unsubscribe
        return unless @active

        @bus.off(@event_type, @handler)
        @active = false
      end

      # Check if still subscribed
      # @return [Boolean] True if active
      def subscribed?
        @active
      end
    end
  end
end
