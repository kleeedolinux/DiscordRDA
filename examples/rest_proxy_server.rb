# frozen_string_literal: true

require 'discord_rda'
require 'webrick'
require 'json'

# Simple REST Proxy Server example
# In production, use a proper reverse proxy or dedicated service
# This demonstrates the concept of centralizing REST API access

class RestProxyServer
  def initialize(port: 8000, discord_token: nil)
    @port = port
    @discord_token = discord_token
    @server = nil
    @logger = Logger.new(STDOUT)
    @request_counts = Hash.new(0)
    @rate_limits = {}
  end

  def start
    @server = WEBrick::HTTPServer.new(Port: @port, Logger: @logger, AccessLog: [])

    # Health check endpoint
    @server.mount_proc '/health' do |req, res|
      res.content_type = 'application/json'
      res.body = {
        status: 'healthy',
        timestamp: Time.now.utc.iso8601,
        workers: @request_counts.keys.length,
        total_requests: @request_counts.values.sum
      }.to_json
    end

    # Proxy all Discord API requests
    @server.mount_proc '/api' do |req, res|
      handle_proxy_request(req, res)
    end

    # Catch-all for Discord API routes
    @server.mount_proc '/' do |req, res|
      if req.path.start_with?('/api/')
        handle_proxy_request(req, res)
      else
        res.status = 404
        res.body = { error: 'Not found' }.to_json
      end
    end

    puts "🌐 REST Proxy Server starting on port #{@port}"
    puts "   Workers can connect to: http://localhost:#{@port}"

    Thread.new { @server.start }
  end

  def stop
    @server&.shutdown
  end

  private

  def handle_proxy_request(req, res)
    # Authenticate worker
    auth = req['Authorization']
    unless authenticate_worker(auth)
      res.status = 401
      res.body = { error: 'Unauthorized' }.to_json
      return
    end

    # Track request
    worker_id = auth || 'anonymous'
    @request_counts[worker_id] += 1

    # Check rate limits
    if rate_limited?(req.path)
      res.status = 429
      res['Retry-After'] = '1'
      res.body = { error: 'Rate limited', retry_after: 1 }.to_json
      return
    end

    # Forward to Discord (simplified - real impl would use actual REST client)
    res.content_type = 'application/json'
    res.body = {
      proxied: true,
      path: req.path,
      method: req.request_method,
      worker: worker_id,
      timestamp: Time.now.utc.iso8601
    }.to_json
  end

  def authenticate_worker(auth)
    # In production, validate against stored worker tokens
    auth && !auth.empty?
  end

  def rate_limited?(path)
    # Simplified rate limiting
    # Real implementation would track Discord rate limits
    false
  end
end

# Start proxy if run directly
if __FILE__ == $0
  proxy = RestProxyServer.new(
    port: ENV['PROXY_PORT']&.to_i || 8000,
    discord_token: ENV['DISCORD_TOKEN']
  )

  proxy.start

  puts "Press Ctrl+C to stop"
  sleep
end
