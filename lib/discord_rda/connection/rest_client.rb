# frozen_string_literal: true

require 'async/http/internet'
require 'async/http/endpoint'
require 'cgi'
require 'net/http/post/multipart'

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
    # @param files [Hash] Files to upload (field_name => File or IO)
    # @return [Hash] Response data
    def post(path, body: nil, params: {}, headers: {}, files: nil)
      if files
        request_multipart(:post, path, body: body, files: files, params: params, headers: headers)
      else
        request(:post, path, body: body, params: params, headers: headers)
      end
    end

    # Make a PUT request
    # @param path [String] API path
    # @param body [Object] Request body
    # @param params [Hash] Query parameters
    # @param headers [Hash] Additional headers
    # @param files [Hash] Files to upload (field_name => File or IO)
    # @return [Hash] Response data
    def put(path, body: nil, params: {}, headers: {}, files: nil)
      if files
        request_multipart(:put, path, body: body, files: files, params: params, headers: headers)
      else
        request(:put, path, body: body, params: params, headers: headers)
      end
    end

    # Make a PATCH request
    # @param path [String] API path
    # @param body [Object] Request body
    # @param params [Hash] Query parameters
    # @param headers [Hash] Additional headers
    # @param files [Hash] Files to upload (field_name => File or IO)
    # @return [Hash] Response data
    def patch(path, body: nil, params: {}, headers: {}, files: nil)
      if files
        request_multipart(:patch, path, body: body, files: files, params: params, headers: headers)
      else
        request(:patch, path, body: body, params: params, headers: headers)
      end
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

    def request_multipart(method, path, body: nil, files: {}, params: {}, headers: {})
      require 'securerandom'

      url = build_url(path, params)
      route = extract_route(method, path)

      # Wait for rate limit
      @rate_limiter.acquire(route)

      # Build multipart body
      boundary = SecureRandom.hex(16)
      multipart_headers = headers.merge(
        'Authorization' => "Bot #{@config.token}",
        'User-Agent' => "DiscordRDA (https://github.com/juliaklee/discord_rda, #{VERSION})",
        'Content-Type' => "multipart/form-data; boundary=#{boundary}"
      )

      # Build multipart body manually for Async::HTTP compatibility
      parts = []

      # Add JSON payload as 'payload_json' field if body provided
      if body
        parts << build_multipart_field('payload_json', Oj.dump(body, mode: :compat), boundary)
      end

      # Add files
      files.each do |field_name, file|
        parts << build_multipart_file(field_name, file, boundary)
      end

      # Close boundary
      parts << "--#{boundary}--\r\n"

      multipart_body = parts.join

      start_time = Time.now
      response = make_multipart_http_request(method, url, multipart_body, multipart_headers)
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

    def build_multipart_field(name, value, boundary)
      "--#{boundary}\r\n" \
      "Content-Disposition: form-data; name=\"#{name}\"\r\n" \
      "Content-Type: application/json\r\n\r\n" \
      "#{value}\r\n"
    end

    def build_multipart_file(field_name, file, boundary)
      filename = file.respond_to?(:original_filename) ? file.original_filename : File.basename(file.path)
      content_type = file.respond_to?(:content_type) ? file.content_type : 'application/octet-stream'
      content = file.respond_to?(:read) ? file.read : File.read(file)

      "--#{boundary}\r\n" \
      "Content-Disposition: form-data; name=\"#{field_name}\"; filename=\"#{filename}\"\r\n" \
      "Content-Type: #{content_type}\r\n\r\n" \
      "#{content}\r\n"
    end

    def make_multipart_http_request(method, url, body, headers)
      case method
      when :post
        @internet.post(url, headers, body)
      when :put
        @internet.put(url, headers, body)
      when :patch
        @internet.patch(url, headers, body)
      else
        raise ArgumentError, "Multipart not supported for #{method}"
      end
    end

    def handle_response(response)
      body = response.read
      data = parse_response_body(body)

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

    def parse_response_body(body)
      return nil if body.nil? || body.empty?

      Oj.load(body)
    rescue Oj::ParseError
      body
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
