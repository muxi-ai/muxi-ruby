# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"
require "logger"

module Muxi
  class Transport
    attr_reader :base_url, :key_id, :secret_key, :timeout, :max_retries, :debug, :logger

    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze

    def initialize(base_url:, key_id:, secret_key:, timeout: 30, max_retries: 0, debug: false, logger: nil)
      @base_url = base_url.chomp("/")
      @key_id = (key_id || "").strip
      @secret_key = (secret_key || "").strip
      @timeout = timeout || 30
      @max_retries = max_retries || 0
      @debug = debug || Muxi.debug?
      @logger = logger || Logger.new($stdout, level: Logger::DEBUG)
    end

    def request_json(method, path, params: nil, body: nil)
      url, full_path = build_url(path, params)
      headers = build_headers(method, full_path)

      attempt = 0
      backoff = 0.5

      loop do
        start_time = Time.now
        begin
          response = execute_request(method, url, headers, body)
          elapsed = Time.now - start_time
          log("#{method} #{full_path} -> #{response.code} (#{elapsed.round(3)}s)")

          if response.code.to_i >= 400
            handle_error_response(response, method, url, attempt, backoff)
            backoff *= 2
            attempt += 1
            next if attempt <= @max_retries
          end

          return parse_response(response)
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::OpenTimeout, SocketError => e
          if attempt < @max_retries
            sleep_for = [backoff, 30].min
            log("retry #{method} #{full_path} after #{sleep_for}s due to connection error: #{e}")
            sleep(sleep_for)
            backoff *= 2
            attempt += 1
            next
          end
          raise ConnectionError.new("CONNECTION_ERROR", e.message, 0)
        end
      end
    end

    def stream_lines(method, path, params: nil, body: nil, &block)
      url, full_path = build_url(path, params)
      headers = build_headers(method, full_path, accept: "text/event-stream")
      
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = nil # infinite for streaming

      request = build_request(method, uri, headers, body)
      
      http.request(request) do |response|
        response.read_body do |chunk|
          chunk.each_line do |line|
            yield line
          end
        end
      end
    end

    private

    def build_url(path, params)
      rel_path = path.start_with?("/") ? path : "/#{path}"
      query = params&.compact&.map { |k, v| "#{k}=#{URI.encode_www_form_component(v.to_s)}" }&.join("&")
      full_path = query && !query.empty? ? "#{rel_path}?#{query}" : rel_path
      ["#{@base_url}#{full_path}", full_path]
    end

    def build_headers(method, path, accept: nil)
      {
        "Authorization" => Auth.build_auth_header(@key_id, @secret_key, method, path),
        "Content-Type" => "application/json",
        "Accept" => accept || "application/json",
        "X-Muxi-SDK" => "ruby/#{VERSION}",
        "X-Muxi-Client" => "#{RUBY_PLATFORM}/ruby#{RUBY_VERSION}",
        "X-Muxi-Idempotency-Key" => SecureRandom.uuid
      }
    end

    def build_request(method, uri, headers, body)
      klass = case method.upcase
              when "GET" then Net::HTTP::Get
              when "POST" then Net::HTTP::Post
              when "PUT" then Net::HTTP::Put
              when "DELETE" then Net::HTTP::Delete
              when "PATCH" then Net::HTTP::Patch
              else raise ArgumentError, "Unknown HTTP method: #{method}"
              end

      request = klass.new(uri.request_uri)
      headers.each { |k, v| request[k] = v }
      request.body = body.to_json if body
      request
    end

    def execute_request(method, url, headers, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout
      http.read_timeout = @timeout

      request = build_request(method, uri, headers, body)
      http.request(request)
    end

    def handle_error_response(response, method, url, attempt, backoff)
      status = response.code.to_i
      retry_after = response["Retry-After"]&.to_i

      payload = begin
        JSON.parse(response.body)
      rescue
        nil
      end

      code = payload&.dig("code") || payload&.dig("error") || "ERROR"
      message = payload&.dig("message") || response.message

      if RETRY_STATUSES.include?(status) && attempt < @max_retries
        sleep_for = [backoff, 30].min
        log("retry #{method} #{url} after #{sleep_for}s due to #{status}")
        sleep(sleep_for)
        return
      end

      raise Muxi.map_error(status, code, message, payload, retry_after)
    end

    def parse_response(response)
      return nil if response.body.nil? || response.body.empty?

      begin
        parsed = JSON.parse(response.body)
        unwrap_envelope(parsed)
      rescue JSON::ParserError
        response.body
      end
    end

    def unwrap_envelope(obj)
      return obj unless obj.is_a?(Hash) && obj.key?("data")

      req = obj["request"] || {}
      request_id = req["id"] || obj["request_id"]
      ts = obj["timestamp"]
      data = obj["data"]

      if data.is_a?(Hash)
        out = data.dup
        out["request_id"] ||= request_id if request_id
        out["timestamp"] ||= ts if ts
        out
      else
        data.nil? ? obj : data
      end
    end

    def log(msg)
      @logger.debug("[MUXI] #{msg}") if @debug
    end
  end
end
