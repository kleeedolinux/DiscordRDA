# frozen_string_literal: true

module DiscordRDA
  # REST Proxy for horizontal scaling.
  # Allows multiple bot processes to share a single REST connection pool.
  #
  class RestProxy
    # @return [String] Proxy base URL
    attr_reader :base_url

    # @return [String] Proxy authorization token
    attr_reader :authorization

    # @return [Logger] Logger instance
    attr_reader :logger

    # @return [Hash] Active connections
    attr_reader :connections

    # Initialize REST proxy client
    # @param base_url [String] Proxy base URL
    # @param authorization [String] Proxy authorization
    # @param logger [Logger] Logger instance
    def initialize(base_url:, authorization:, logger: nil)
      @base_url = base_url
      @authorization = authorization
      @logger = logger
      @connections = {}
      @mutex = Mutex.new
      @internet = nil
    end

    # Start the proxy client
    # @return [void]
    def start
      @internet = Async::HTTP::Internet.new
    end

    # Stop the proxy client
    # @return [void]
    def stop
      @internet&.close
      @internet = nil
    end

    # Forward a request to the proxy
    # @param method [Symbol] HTTP method
    # @param route [String] API route
    # @param options [Hash] Request options
    # @return [Hash] Response data
    def forward(method, route, options = {})
      url = "#{@base_url}#{route}"

      headers = {
        'Authorization' => @authorization,
        'Content-Type' => 'application/json',
        'X-Proxy-Method' => method.to_s.upcase
      }.merge(options[:headers] || {})

      body = options[:body] ? Oj.dump(options[:body]) : nil

      response = case method
                 when :get
                   @internet.get(url, headers)
                 when :post
                   @internet.post(url, headers, body)
                 when :put
                   @internet.put(url, headers, body)
                 when :patch
                   @internet.patch(url, headers, body)
                 when :delete
                   @internet.delete(url, headers)
                 end

      handle_response(response)
    end

    # Get proxy health/status
    # @return [Hash] Status information
    def health_check
      begin
        response = @internet.get("#{@base_url}/health", {})
        {
          healthy: response.status == 200,
          status: response.status,
          timestamp: Time.now.utc
        }
      rescue => e
        {
          healthy: false,
          error: e.message,
          timestamp: Time.now.utc
        }
      end
    end

    # Register a bot instance with the proxy
    # @param bot_id [String] Bot ID
    # @param token [String] Bot token
    # @return [Hash] Registration response
    def register_bot(bot_id, token)
      response = @internet.post(
        "#{@base_url}/register",
        {
          'Authorization' => @authorization,
          'Content-Type' => 'application/json'
        },
        Oj.dump({ bot_id: bot_id, token: token })
      )

      handle_response(response)
    end

    # Update bearer token (for OAuth2 bots)
    # @param old_token [String] Old token
    # @param new_token [String] New token
    # @return [void]
    def update_token(old_token, new_token)
      @internet.post(
        "#{@base_url}/update-token",
        {
          'Authorization' => @authorization,
          'Content-Type' => 'application/json'
        },
        Oj.dump({ old_token: old_token, new_token: new_token })
      )
    end

    private

    def handle_response(response)
      body = response.read
      data = if body.nil? || body.empty?
               nil
             else
               Oj.load(body)
             end

      case response.status
      when 200..299
        data
      when 429
        retry_after = data['retry_after'] || 1.0
        raise RateLimitedError.new(response.status, data, retry_after: retry_after)
      else
        raise APIError.new(response.status, data)
      end
    end

    class APIError < StandardError
      attr_reader :status, :data

      def initialize(status, data)
        @status = status
        @data = data || {}
        super("Proxy API Error #{status}: #{@data['message'] || 'Unknown'}")
      end
    end

    class RateLimitedError < APIError
      attr_reader :retry_after

      def initialize(status, data, retry_after:)
        super(status, data)
        @retry_after = retry_after
      end
    end
  end
end
