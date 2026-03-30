# frozen_string_literal: true

module DiscordRDA
  # Enhanced scalable REST client inspired by Discordeno.
  # Features: request queues, invalid request bucket, URL simplification, proxy support.
  #
  class ScalableRestClient
    # Discord API base URL
    API_BASE = 'https://discord.com/api/v10'

    # Rate limit headers
    RATE_LIMIT_REMAINING_HEADER = 'x-ratelimit-remaining'
    RATE_LIMIT_RESET_AFTER_HEADER = 'x-ratelimit-reset-after'
    RATE_LIMIT_GLOBAL_HEADER = 'x-ratelimit-global'
    RATE_LIMIT_BUCKET_HEADER = 'x-ratelimit-bucket'
    RATE_LIMIT_LIMIT_HEADER = 'x-ratelimit-limit'

    # Major parameters that affect rate limit buckets
    MAJOR_PARAMS = %w[channels guilds webhooks].freeze

    # @return [Configuration] Configuration instance
    attr_reader :config

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [InvalidRequestBucket] Invalid request bucket
    attr_reader :invalid_bucket

    # @return [Hash<String, RequestQueue>] Request queues
    attr_reader :queues

    # @return [Hash<String, Hash>] Rate limited paths
    attr_reader :rate_limited_paths

    # @return [Boolean] Whether globally rate limited
    attr_accessor :globally_rate_limited

    # @return [Boolean] Whether processing rate limited paths
    attr_accessor :processing_rate_limited_paths

    # @return [Integer] Delay before deleting empty queue (ms)
    attr_reader :delete_queue_delay

    # @return [Integer] Maximum retry count
    attr_reader :max_retry_count

    # @return [Boolean] Whether using proxy
    attr_reader :is_proxied

    # @return [String] Proxy base URL
    attr_reader :proxy_base_url

    # @return [String] Proxy authorization
    attr_reader :proxy_authorization

    # Initialize the scalable REST client
    # @param config [Configuration] Bot configuration
    # @param logger [Logger] Logger instance
    # @param proxy [Hash] Proxy configuration (base_url, authorization)
    def initialize(config, logger, proxy: nil)
      @config = config
      @logger = logger
      @invalid_bucket = InvalidRequestBucket.new(logger: logger)
      @queues = {}
      @rate_limited_paths = {}
      @globally_rate_limited = false
      @processing_rate_limited_paths = false
      @delete_queue_delay = 60_000
      @max_retry_count = Float::INFINITY
      @mutex = Mutex.new
      @internet = nil

      # Proxy configuration for horizontal scaling
      if proxy
        @is_proxied = true
        @proxy_base_url = proxy[:base_url]
        @proxy_authorization = proxy[:authorization]
      else
        @is_proxied = false
        @proxy_base_url = API_BASE
      end
    end

    # Start the REST client
    # @return [void]
    def start
      @internet = Async::HTTP::Internet.new
      process_rate_limited_paths
    end

    # Stop the REST client
    # @return [void]
    def stop
      @internet&.close
      @internet = nil
    end

    # Make a GET request
    # @param route [String] API route
    # @param options [Hash] Request options
    # @return [Hash] Response data
    def get(route, options = {})
      make_request(:get, route, options)
    end

    # Make a POST request
    # @param route [String] API route
    # @param options [Hash] Request options
    # @return [Hash] Response data
    def post(route, options = {})
      make_request(:post, route, options)
    end

    # Make a PUT request
    # @param route [String] API route
    # @param options [Hash] Request options
    # @return [Hash] Response data
    def put(route, options = {})
      make_request(:put, route, options)
    end

    # Make a PATCH request
    # @param route [String] API route
    # @param options [Hash] Request options
    # @return [Hash] Response data
    def patch(route, options = {})
      make_request(:patch, route, options)
    end

    # Make a DELETE request
    # @param route [String] API route
    # @param options [Hash] Request options
    # @return [Hash] Response data
    def delete(route, options = {})
      make_request(:delete, route, options)
    end

    # Simplify URL for rate limit bucket identification
    # @param url [String] Full URL
    # @param method [Symbol] HTTP method
    # @return [String] Simplified URL for bucket
    def simplify_url(url, method)
      # Split URL into parts
      parts = url.split('/').reject(&:empty?)

      # Build simplified URL
      simplified = [method.to_s.upcase]

      parts.each_with_index do |part, index|
        # Check if this is a major parameter (channels, guilds, webhooks)
        if MAJOR_PARAMS.include?(part)
          simplified << part
          # Keep the ID after major params
          if parts[index + 1] && parts[index + 1] =~ /^\d+$/
            simplified << parts[index + 1]
          end
        elsif part =~ /^\d+$/
          # Replace numeric IDs with 'x' unless after major param
          prev = parts[index - 1]
          simplified << 'x' unless MAJOR_PARAMS.include?(prev)
        else
          simplified << part
        end
      end

      # Special handling for reactions
      if url.include?('/reactions/')
        # Simplify reactions path: /reactions/emoji/@me or /reactions/emoji/user_id
        simplified = simplify_reactions_url(simplified)
      end

      # Special handling for messages
      if url.include?('/messages/')
        # Keep method in front for messages
        simplified = simplify_messages_url(method, parts)
      end

      simplified.join('/')
    end

    # Check rate limits for a URL or bucket
    # @param url [String] URL or bucket ID
    # @param identifier [String] Queue identifier
    # @return [Integer, false] Milliseconds until reset, or false if not limited
    def check_rate_limits(url, identifier)
      @mutex.synchronize do
        # Check specific URL rate limit
        limited = @rate_limited_paths["#{identifier}#{url}"]
        global = @rate_limited_paths['global']
        now = Time.now.to_f * 1000

        if limited && now < limited[:reset_timestamp]
          return limited[:reset_timestamp] - now
        end

        if global && now < global[:reset_timestamp]
          return global[:reset_timestamp] - now
        end

        false
      end
    end

    # Process rate limited paths (cleanup loop)
    # @return [void]
    def process_rate_limited_paths
      @mutex.synchronize do
        now = Time.now.to_f * 1000

        @rate_limited_paths.delete_if do |key, value|
          if value[:reset_timestamp] <= now
            # If it was global, mark as not globally rate limited
            @globally_rate_limited = false if key == 'global'
            true # Delete this entry
          else
            false # Keep this entry
          end
        end

        # If all paths are cleared, stop processing
        if @rate_limited_paths.empty?
          @processing_rate_limited_paths = false
        else
          @processing_rate_limited_paths = true
          # Recheck in 1 second
          Async { sleep(1); process_rate_limited_paths }
        end
      end
    end

    # Update token in all queues (for token refresh)
    # @param old_token [String] Old token
    # @param new_token [String] New token
    # @return [void]
    def update_token_queues(old_token, new_token)
      @mutex.synchronize do
        old_identifier = "Bearer #{old_token}"
        new_identifier = "Bearer #{new_token}"

        # Update queues
        @queues.delete_if do |key, queue|
          next false unless key.start_with?(old_identifier)

          @queues.delete(key)
          queue.identifier = new_identifier

          new_key = "#{new_identifier}#{queue.url}"
          existing = @queues[new_key]

          if existing
            # Merge queues
            existing.pending.concat(queue.pending)
            queue.pending.clear
            queue.cleanup
            true # Delete old queue
          else
            @queues[new_key] = queue
            false # Don't delete, we moved it
          end
        end

        # Update rate limited paths
        @rate_limited_paths.delete_if do |key, path|
          next false unless key.start_with?(old_identifier)

          @rate_limited_paths["#{new_identifier}#{path[:url]}"] = path

          if path[:bucket_id]
            @rate_limited_paths["#{new_identifier}#{path[:bucket_id]}"] = path
          end

          true # Delete old entry
        end
      end
    end

    private

    def make_request(method, route, options = {})
      url = simplify_url(route, method)
      identifier = options[:authorization] || "Bot #{@config.token}"

      # Create queue if doesn't exist
      queue = @mutex.synchronize do
        @queues["#{identifier}#{url}"] ||= RequestQueue.new(
          self,
          url: url,
          identifier: identifier,
          delete_queue_delay: @delete_queue_delay
        )
      end

      # Add request to queue
      promise = Async::Condition.new

      request = {
        method: method,
        route: route,
        body: options[:body],
        headers: options[:headers],
        bucket_id: options[:bucket_id],
        resolve: ->(result) { promise.signal(result) },
        reject: ->(error) { promise.signal(error) }
      }

      queue.make_request(request)

      # Wait for result
      result = promise.wait

      # Check if it's an error
      raise result[:error] if result.is_a?(Hash) && result[:error]

      result
    end

    def send_request(request)
      full_url = "#{@proxy_base_url}/v#{@config.api_version}#{request[:route]}"

      # Build headers
      headers = build_headers(request[:headers])

      # Make request
      response = make_http_request(request[:method], full_url, request[:body], headers)

      # Process response
      process_response(response, request)
    rescue => e
      @logger.error('Request failed', error: e, route: request[:route])
      raise
    end

    def make_http_request(method, url, body, headers)
      body_json = body ? Oj.dump(body, mode: :compat) : nil

      case method
      when :get
        @internet.get(url, headers)
      when :post
        @internet.post(url, headers, body_json)
      when :put
        @internet.put(url, headers, body_json)
      when :patch
        @internet.patch(url, headers, body_json)
      when :delete
        @internet.delete(url, headers)
      else
        raise ArgumentError, "Unknown HTTP method: #{method}"
      end
    end

    def process_response(response, request)
      status = response.status
      body = response.read
      data = body ? Oj.load(body) : nil

      # Handle invalid request tracking
      @invalid_bucket.handle_request(status)

      # Process rate limit headers
      bucket_id = process_headers(request[:route], response.headers, request[:identifier])

      # Update queue with rate limit info
      url = simplify_url(request[:route], request[:method])
      queue = @queues["#{request[:identifier]}#{url}"]

      if queue
        queue.handle_completed_request(
          max: response.headers[RATE_LIMIT_LIMIT_HEADER]&.to_i,
          remaining: response.headers[RATE_LIMIT_REMAINING_HEADER]&.to_i,
          interval: response.headers[RATE_LIMIT_RESET_AFTER_HEADER]&.to_f&.*(1000)
        )
      end

      case status
      when 200..299
        data
      when 400
        raise BadRequestError.new(status, data)
      when 401
        raise UnauthorizedError.new(status, data)
      when 403
        raise ForbiddenError.new(status, data)
      when 404
        raise NotFoundError.new(status, data)
      when 429
        retry_after = data['retry_after'] || response.headers['retry-after']&.to_f
        raise RateLimitedError.new(status, data, retry_after: retry_after)
      when 500..599
        raise ServerError.new(status, data)
      else
        raise APIError.new(status, data)
      end
    end

    def process_headers(url, headers, identifier)
      remaining = headers[RATE_LIMIT_REMAINING_HEADER]
      retry_after = headers['Retry-After'] || headers[RATE_LIMIT_RESET_AFTER_HEADER]
      reset = Time.now.to_f * 1000 + retry_after.to_f * 1000 if retry_after
      global = headers[RATE_LIMIT_GLOBAL_HEADER]
      bucket_id = headers[RATE_LIMIT_BUCKET_HEADER]
      identifier ||= "Bot #{@config.token}"

      rate_limited = false

      # If no remaining, mark as rate limited
      if remaining == '0'
        rate_limited = true

        @mutex.synchronize do
          @rate_limited_paths["#{identifier}#{url}"] = {
            url: url,
            reset_timestamp: reset,
            bucket_id: bucket_id
          }

          if bucket_id
            @rate_limited_paths["#{identifier}#{bucket_id}"] = {
              url: url,
              reset_timestamp: reset,
              bucket_id: bucket_id
            }
          end
        end
      end

      # Handle global rate limit
      if global
        retry_ms = headers['retry-after'].to_f * 1000
        global_reset = Time.now.to_f * 1000 + retry_ms

        @globally_rate_limited = true
        rate_limited = true

        @mutex.synchronize do
          @rate_limited_paths['global'] = {
            url: 'global',
            reset_timestamp: global_reset,
            bucket_id: bucket_id
          }
        end

        Async { sleep(retry_ms / 1000.0); @globally_rate_limited = false }
      end

      # Start processing rate limited paths if needed
      if rate_limited && !@processing_rate_limited_paths
        process_rate_limited_paths
      end

      bucket_id if rate_limited
    end

    def build_headers(additional = {})
      base = {
        'User-Agent' => "DiscordRDA (https://github.com/juliaklee/discord_rda, #{VERSION})",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }

      # Add authorization
      if @is_proxied && @proxy_authorization
        base['Authorization'] = @proxy_authorization
      else
        base['Authorization'] = "Bot #{@config.token}"
      end

      base.merge(additional || {})
    end

    def simplify_reactions_url(parts)
      # Convert reactions/emoji to reactions/x
      parts.map { |p| p =~ /^[\w-]+$/ && p.length > 10 ? 'x' : p }
    end

    def simplify_messages_url(method, parts)
      result = [method.to_s.upcase]

      parts.each_with_index do |part, index|
        if MAJOR_PARAMS.include?(part)
          result << part
          # Keep ID after major param
          result << parts[index + 1] if parts[index + 1] && parts[index + 1] =~ /^\d+$/
        elsif part == 'messages' && parts[index + 1] =~ /^\d+$/
          result << part << 'x'
        elsif part =~ /^\d+$/
          prev = parts[index - 1]
          result << 'x' unless MAJOR_PARAMS.include?(prev)
        else
          result << part
        end
      end

      result.uniq
    end

    # Error classes
    class APIError < StandardError
      attr_reader :status, :data

      def initialize(status, data)
        @status = status
        @data = data || {}
        message = @data['message'] || 'Unknown error'
        super("API Error #{status}: #{message}")
      end
    end

    class BadRequestError < APIError; end
    class UnauthorizedError < APIError; end
    class ForbiddenError < APIError; end
    class NotFoundError < APIError; end

    class RateLimitedError < APIError
      attr_reader :retry_after

      def initialize(status, data, retry_after: nil)
        super(status, data)
        @retry_after = retry_after || data['retry_after'] || 1.0
      end
    end

    class ServerError < APIError; end
  end
end
