# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"

module Muxi
  class FormationConfig
    attr_accessor :formation_id, :url, :server_url, :base_url, :admin_key, :client_key,
                  :max_retries, :timeout, :debug, :logger, :mode, :_app

    def initialize(
      formation_id: nil, url: nil, server_url: nil, base_url: nil,
      admin_key: nil, client_key: nil, max_retries: 0, timeout: 30,
      debug: false, logger: nil, mode: "live", _app: nil
    )
      @formation_id = formation_id
      @url = url
      @server_url = server_url
      @base_url = base_url
      @admin_key = admin_key
      @client_key = client_key
      @max_retries = max_retries
      @timeout = timeout
      @debug = debug
      @logger = logger
      @mode = mode
      @_app = _app
    end
  end

  class FormationTransport
    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze

    def initialize(base_url:, admin_key:, client_key:, timeout:, max_retries:, debug:, logger:, app: nil)
      @base_url = base_url.chomp("/")
      @admin_key = (admin_key || "").strip
      @client_key = (client_key || "").strip
      @timeout = timeout || 30
      @max_retries = max_retries || 0
      @debug = debug || Muxi.debug?
      @logger = logger || Logger.new($stdout, level: Logger::DEBUG)
      @app = app
    end

    def request_json(method, path, params: nil, body: nil, use_admin: true, user_id: "")
      url, full_path = build_url(path, params)
      headers = build_headers(use_admin: use_admin, user_id: user_id, content_type: body ? "application/json" : nil)

      attempt = 0
      backoff = 0.5

      loop do
        start_time = Time.now
        begin
          response = execute_request(method, url, headers, body)
          elapsed = Time.now - start_time
          log("#{method} #{full_path} -> #{response.code} (#{elapsed.round(3)}s)")

          # Check for SDK updates (non-blocking, once per process)
          VersionCheck.check_for_updates(response.to_hash.transform_values(&:first))

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

    def stream_sse(method, path, params: nil, body: nil, use_admin: true, user_id: "", &block)
      return enum_for(:stream_sse, method, path, params: params, body: body, use_admin: use_admin, user_id: user_id) unless block_given?

      url, _ = build_url(path, params)
      headers = build_headers(use_admin: use_admin, user_id: user_id, content_type: body ? "application/json" : nil, accept: "text/event-stream")

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = nil

      request = build_request(method, uri, headers, body)
      
      event = nil
      data_parts = []

      http.request(request) do |response|
        response.read_body do |chunk|
          chunk.each_line do |raw_line|
            line = raw_line.chomp
            next if line.start_with?(":")

            if line.empty?
              if data_parts.any?
                yield({ "event" => event || "message", "data" => data_parts.join("\n") })
              end
              event = nil
              data_parts = []
              next
            end

            if line.start_with?("event:")
              event = line[6..].strip
            elsif line.start_with?("data:")
              data_parts << line[5..].strip
            end
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

    def build_headers(use_admin:, user_id:, content_type: nil, accept: nil)
      headers = {
        "X-Muxi-SDK" => "ruby/#{VERSION}",
        "X-Muxi-Client" => "ruby/#{VERSION}",
        "X-Muxi-Idempotency-Key" => SecureRandom.uuid
      }

      headers["X-Muxi-App"] = @app if @app && !@app.empty?

      if use_admin
        raise ArgumentError, "admin key required" if @admin_key.empty?
        headers["X-MUXI-ADMIN-KEY"] = @admin_key
      else
        raise ArgumentError, "client key required" if @client_key.empty?
        headers["X-MUXI-CLIENT-KEY"] = @client_key
      end

      headers["X-Muxi-User-ID"] = user_id if user_id && !user_id.empty?
      headers["Content-Type"] = content_type if content_type
      headers["Accept"] = accept || "application/json"
      headers
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

  class FormationClient
    def initialize(config = nil, **kwargs)
      cfg = config || FormationConfig.new(**kwargs)
      base_url = build_base_url(cfg)
      @transport = FormationTransport.new(
        base_url: base_url,
        admin_key: cfg.admin_key,
        client_key: cfg.client_key,
        timeout: cfg.timeout,
        max_retries: cfg.max_retries,
        debug: cfg.debug,
        logger: cfg.logger,
        app: cfg._app
      )
    end

    # Health / status
    def health
      @transport.request_json("GET", "/health", use_admin: false)
    end

    def get_status
      @transport.request_json("GET", "/status", use_admin: true)
    end

    def get_config
      @transport.request_json("GET", "/config", use_admin: true)
    end

    def get_formation_info
      @transport.request_json("GET", "/formation", use_admin: true)
    end

    # Agents / MCP
    def get_agents
      @transport.request_json("GET", "/agents", use_admin: true)
    end

    def get_agent(agent_id)
      @transport.request_json("GET", "/agents/#{agent_id}", use_admin: true)
    end

    def get_mcp_servers
      @transport.request_json("GET", "/mcp/servers", use_admin: true)
    end

    def get_mcp_server(server_id)
      @transport.request_json("GET", "/mcp/servers/#{server_id}", use_admin: true)
    end

    def get_mcp_tools
      @transport.request_json("GET", "/mcp/tools", use_admin: true)
    end

    # Secrets
    def get_secrets
      @transport.request_json("GET", "/secrets", use_admin: true)
    end

    def get_secret(key)
      @transport.request_json("GET", "/secrets/#{key}", use_admin: true)
    end

    def set_secret(key, value)
      @transport.request_json("PUT", "/secrets/#{key}", body: { value: value }, use_admin: true)
    end

    def delete_secret(key)
      @transport.request_json("DELETE", "/secrets/#{key}", use_admin: true)
    end

    # Chat
    def chat(payload, user_id: "")
      @transport.request_json("POST", "/chat", body: payload, use_admin: false, user_id: user_id)
    end

    def chat_stream(payload, user_id: "", &block)
      body = payload.merge(stream: true)
      @transport.stream_sse("POST", "/chat", body: body, use_admin: false, user_id: user_id, &block)
    end

    def audio_chat(payload, user_id: "")
      @transport.request_json("POST", "/audiochat", body: payload, use_admin: false, user_id: user_id)
    end

    def audio_chat_stream(payload, user_id: "", &block)
      body = payload.merge(stream: true)
      @transport.stream_sse("POST", "/audiochat", body: body, use_admin: false, user_id: user_id, &block)
    end

    # Sessions / requests
    def get_sessions(user_id, limit: nil)
      params = { user_id: user_id, limit: limit }
      @transport.request_json("GET", "/sessions", params: params, use_admin: false, user_id: user_id)
    end

    def get_session(session_id, user_id)
      @transport.request_json("GET", "/sessions/#{session_id}", use_admin: false, user_id: user_id)
    end

    def get_session_messages(session_id, user_id)
      @transport.request_json("GET", "/sessions/#{session_id}/messages", use_admin: false, user_id: user_id)
    end

    def restore_session(session_id, user_id, messages)
      @transport.request_json("POST", "/sessions/#{session_id}/restore", body: { messages: messages }, use_admin: false, user_id: user_id)
    end

    def get_requests(user_id)
      @transport.request_json("GET", "/requests", use_admin: false, user_id: user_id)
    end

    def get_request_status(request_id, user_id)
      @transport.request_json("GET", "/requests/#{request_id}", use_admin: false, user_id: user_id)
    end

    def cancel_request(request_id, user_id)
      @transport.request_json("DELETE", "/requests/#{request_id}", use_admin: false, user_id: user_id)
    end

    # Memory
    def get_memory_config
      @transport.request_json("GET", "/memory", use_admin: true)
    end

    def get_memories(user_id, limit: nil)
      params = { user_id: user_id, limit: limit }
      @transport.request_json("GET", "/memories", params: params, use_admin: false, user_id: user_id)
    end

    def add_memory(user_id, mem_type, detail)
      @transport.request_json("POST", "/memories", body: { user_id: user_id, type: mem_type, detail: detail }, use_admin: false, user_id: user_id)
    end

    def delete_memory(user_id, memory_id)
      @transport.request_json("DELETE", "/memories/#{memory_id}", params: { user_id: user_id }, use_admin: false, user_id: user_id)
    end

    def get_user_buffer(user_id)
      @transport.request_json("GET", "/memory/buffer", params: { user_id: user_id }, use_admin: false, user_id: user_id)
    end

    def clear_user_buffer(user_id)
      @transport.request_json("DELETE", "/memory/buffer", params: { user_id: user_id }, use_admin: false, user_id: user_id)
    end

    def clear_session_buffer(user_id, session_id)
      @transport.request_json("DELETE", "/memory/buffer/#{session_id}", params: { user_id: user_id }, use_admin: false, user_id: user_id)
    end

    def clear_all_buffers
      @transport.request_json("DELETE", "/memory/buffer", use_admin: true)
    end

    def get_buffer_stats
      @transport.request_json("GET", "/memory/stats", use_admin: true)
    end

    # Scheduler
    def get_scheduler_config
      @transport.request_json("GET", "/scheduler", use_admin: true)
    end

    def get_scheduler_jobs(user_id)
      @transport.request_json("GET", "/scheduler/jobs", params: { user_id: user_id }, use_admin: true)
    end

    def get_scheduler_job(job_id)
      @transport.request_json("GET", "/scheduler/jobs/#{job_id}", use_admin: true)
    end

    def create_scheduler_job(job_type, schedule, message, user_id)
      body = { type: job_type, schedule: schedule, message: message, user_id: user_id }
      @transport.request_json("POST", "/scheduler/jobs", body: body, use_admin: true)
    end

    def delete_scheduler_job(job_id)
      @transport.request_json("DELETE", "/scheduler/jobs/#{job_id}", use_admin: true)
    end

    # Async / logging / a2a
    def get_async_config
      @transport.request_json("GET", "/async", use_admin: true)
    end

    def get_a2a_config
      @transport.request_json("GET", "/a2a", use_admin: true)
    end

    def get_logging_config
      @transport.request_json("GET", "/logging", use_admin: true)
    end

    def get_logging_destinations
      @transport.request_json("GET", "/logging/destinations", use_admin: true)
    end

    # Credentials / identifiers
    def list_credential_services
      @transport.request_json("GET", "/credentials/services", use_admin: true)
    end

    def list_credentials(user_id)
      @transport.request_json("GET", "/credentials", use_admin: false, user_id: user_id)
    end

    def get_credential(credential_id, user_id)
      @transport.request_json("GET", "/credentials/#{credential_id}", use_admin: false, user_id: user_id)
    end

    def create_credential(user_id, payload)
      @transport.request_json("POST", "/credentials", body: payload, use_admin: false, user_id: user_id)
    end

    def delete_credential(credential_id, user_id)
      @transport.request_json("DELETE", "/credentials/#{credential_id}", use_admin: false, user_id: user_id)
    end

    def get_user_identifiers_for_user(user_id)
      @transport.request_json("GET", "/users/identifiers/#{user_id}", use_admin: true)
    end

    def link_user_identifier(muxi_user_id, identifiers)
      @transport.request_json("POST", "/users/identifiers", body: { muxi_user_id: muxi_user_id, identifiers: identifiers }, use_admin: true)
    end

    def unlink_user_identifier(identifier)
      @transport.request_json("DELETE", "/users/identifiers/#{identifier}", use_admin: true)
    end

    # Overlord / LLM
    def get_overlord_config
      @transport.request_json("GET", "/overlord", use_admin: true)
    end

    def get_overlord_soul
      @transport.request_json("GET", "/overlord/soul", use_admin: true)
    end

    def get_llm_settings
      @transport.request_json("GET", "/llm/settings", use_admin: true)
    end

    # Triggers / SOP / Audit
    def get_triggers
      @transport.request_json("GET", "/triggers", use_admin: false)
    end

    def get_trigger(name)
      @transport.request_json("GET", "/triggers/#{name}", use_admin: false)
    end

    def fire_trigger(name, data, async_mode: false, user_id: "")
      params = { async: async_mode.to_s }
      @transport.request_json("POST", "/triggers/#{name}", params: params, body: data, use_admin: false, user_id: user_id)
    end

    def get_sops
      @transport.request_json("GET", "/sops", use_admin: false)
    end

    def get_sop(name)
      @transport.request_json("GET", "/sops/#{name}", use_admin: false)
    end

    def get_audit_log
      @transport.request_json("GET", "/audit", use_admin: true)
    end

    def clear_audit_log
      @transport.request_json("DELETE", "/audit?confirm=clear-audit-log", use_admin: true)
    end

    # Streaming
    def stream_events(user_id, &block)
      @transport.stream_sse("GET", "/events", params: { user_id: user_id }, use_admin: false, user_id: user_id, &block)
    end

    def stream_request(user_id, session_id, request_id, &block)
      @transport.stream_sse("GET", "/events/#{session_id}/#{request_id}", use_admin: false, user_id: user_id, &block)
    end

    def stream_logs(filters = nil, &block)
      @transport.stream_sse("GET", "/logs", params: filters, use_admin: true, &block)
    end

    # Resolve user
    def resolve_user(identifier, create_user: false)
      @transport.request_json("POST", "/users/resolve", body: { identifier: identifier, create_user: create_user }, use_admin: false)
    end

    private

    def build_base_url(cfg)
      return cfg.base_url.chomp("/") if cfg.base_url
      return "#{cfg.url.chomp('/')}/v1" if cfg.url
      if cfg.server_url && cfg.formation_id
        prefix = cfg.mode == "draft" ? "draft" : "api"
        return "#{cfg.server_url.chomp('/')}/#{prefix}/#{cfg.formation_id}/v1"
      end
      raise ArgumentError, "must set base_url, url, or server_url+formation_id"
    end
  end
end
