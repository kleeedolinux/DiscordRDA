# frozen_string_literal: true

require 'async/http/internet'
require 'async/http/endpoint'
require 'cgi'

module DiscordRDA
  # HTTP client for Discord REST API.
  # Handles requests, rate limiting, and response parsing.
  #
  class RestClient
    # Discord API base URL
    API_BASE = 'https://discord.com/api/v10'

    # @return [Configuration] Configuration instance
    attr_reader :config

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [RateLimiter] Rate limiter instance
    attr_reader :rate_limiter

    # Initialize the REST client
    # @param config [Configuration] Bot configuration
    # @param logger [Logger] Logger instance
    def initialize(config, logger)
      @config = config
      @logger = logger
      @rate_limiter = RateLimiter.new(logger: logger)
      @internet = nil
      @mutex = Mutex.new
    end

    # Start the HTTP client
    # @return [void]
    def start
      @internet = Async::HTTP::Internet.new
    end

    # Stop the HTTP client
    # @return [void]
    def stop
      @internet&.close
      @internet = nil
    end

    # Make a GET request
    # @param path [String] API path
    # @param params [Hash] Query parameters
    # @param headers [Hash] Additional headers
    # @return [Hash] Response data
    def get(path, params: {}, headers: {})
      request(:get, path, params: params, headers: headers)
    end

    # Make a POST request
    # @param path [String] API path
    # @param body [Object] Request body
    # @param params [Hash] Query parameters
    # @param headers [Hash] Additional headers
    # @return [Hash] Response data
    def post(path, body: nil, params: {}, headers: {})
      request(:post, path, body: body, params: params, headers: headers)
    end

    # Make a PUT request
    # @param path [String] API path
    # @param body [Object] Request body
    # @param params [Hash] Query parameters
    # @param headers [Hash] Additional headers
    # @return [Hash] Response data
    def put(path, body: nil, params: {}, headers: {})
      request(:put, path, body: body, params: params, headers: headers)
    end

    # Make a PATCH request
    # @param path [String] API path
    # @param body [Object] Request body
    # @param params [Hash] Query parameters
    # @param headers [Hash] Additional headers
    # @return [Hash] Response data
    def patch(path, body: nil, params: {}, headers: {})
      request(:patch, path, body: body, params: params, headers: headers)
    end

    # Make a DELETE request
    # @param path [String] API path
    # @param params [Hash] Query parameters
    # @param headers [Hash] Additional headers
    # @return [Hash] Response data
    def delete(path, params: {}, headers: {})
      request(:delete, path, params: params, headers: headers)
    end

    private

    def request(method, path, body: nil, params: {}, headers: {})
      url = build_url(path, params)
      request_headers = build_headers(headers)
      route = extract_route(method, path)

      # Wait for rate limit
      @rate_limiter.acquire(route)

      start_time = Time.now
      response = make_http_request(method, url, body, request_headers)
      duration = Time.now - start_time

      # Update rate limit info
      @rate_limiter.update(route, response)

      # Log request
      @logger&.debug('REST request', method: method, path: path, status: response.status, duration: duration)

      # Handle response
      handle_response(response)
    rescue => e
      @logger&.error('REST request failed', method: method, path: path, error: e)
      raise
    end

    def build_url(path, params)
      url = "#{API_BASE}#{path}"
      return url if params.empty?

      query = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
      "#{url}?#{query}"
    end

    def build_headers(additional = {})
      {
        'Authorization' => "Bot #{@config.token}",
        'User-Agent' => "DiscordRDA (https://github.com/juliaklee/discord_rda, #{VERSION})",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }.merge(additional)
    end

    def extract_route(method, path)
      # Extract major parameters for rate limiting
      # Discord uses major parameters (guild_id, channel_id, webhook_id) for route buckets
      route_path = path.gsub(%r{\d{17,}}, ':id')
      "#{method.upcase}:#{route_path}"
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

    def handle_response(response)
      body = response.read
      data = body ? Oj.load(body) : nil

      case response.status
      when 200..299
        data
      when 400
        raise BadRequestError.new(response.status, data)
      when 401
        raise UnauthorizedError.new(response.status, data)
      when 403
        raise ForbiddenError.new(response.status, data)
      when 404
        raise NotFoundError.new(response.status, data)
      when 429
        raise RateLimitedError.new(response.status, data)
      when 500..599
        raise ServerError.new(response.status, data)
      else
        raise APIError.new(response.status, data)
      end
    end

    # REST API Errors
    class APIError < StandardError
      attr_reader :status, :data, :code, :message

      def initialize(status, data)
        @status = status
        @data = data || {}
        @code = @data['code']
        @message = @data['message'] || 'Unknown error'
        super("API Error #{status}: #{@message}")
      end
    end

    class BadRequestError < APIError; end
    class UnauthorizedError < APIError; end
    class ForbiddenError < APIError; end
    class NotFoundError < APIError; end
    class RateLimitedError < APIError
      attr_reader :retry_after

      def initialize(status, data)
        super
        @retry_after = data['retry_after'] || 1.0
      end
    end
    class ServerError < APIError; end
  end
end
