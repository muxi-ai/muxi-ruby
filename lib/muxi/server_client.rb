# frozen_string_literal: true

module Muxi
  class ServerConfig
    attr_accessor :url, :key_id, :secret_key, :max_retries, :timeout, :debug, :logger

    def initialize(url:, key_id:, secret_key:, max_retries: 0, timeout: 30, debug: false, logger: nil)
      @url = url
      @key_id = key_id
      @secret_key = secret_key
      @max_retries = max_retries
      @timeout = timeout
      @debug = debug
      @logger = logger
    end
  end

  class ServerClient
    def initialize(config = nil, **kwargs)
      cfg = config || ServerConfig.new(**kwargs)
      @transport = Transport.new(
        base_url: cfg.url,
        key_id: cfg.key_id,
        secret_key: cfg.secret_key,
        timeout: cfg.timeout,
        max_retries: cfg.max_retries,
        debug: cfg.debug,
        logger: cfg.logger
      )
    end

    # Unauthenticated
    def ping
      resp = @transport.request_json("GET", "/ping")
      resp.is_a?(Hash) ? resp.size : 0
    end

    def health
      @transport.request_json("GET", "/health")
    end

    # Authenticated - Server management
    def status
      rpc_get("/rpc/server/status")
    end

    def list_formations
      rpc_get("/rpc/formations")
    end

    def get_formation(formation_id)
      rpc_get("/rpc/formations/#{formation_id}")
    end

    def stop_formation(formation_id)
      rpc_post("/rpc/formations/#{formation_id}/stop", {})
    end

    def start_formation(formation_id)
      rpc_post("/rpc/formations/#{formation_id}/start", {})
    end

    def restart_formation(formation_id)
      rpc_post("/rpc/formations/#{formation_id}/restart", {})
    end

    def rollback_formation(formation_id)
      rpc_post("/rpc/formations/#{formation_id}/rollback", {})
    end

    def delete_formation(formation_id)
      rpc_delete("/rpc/formations/#{formation_id}")
    end

    def cancel_update(formation_id)
      rpc_post("/rpc/formations/#{formation_id}/cancel-update", {})
    end

    def deploy_formation(formation_id, payload)
      rpc_post("/rpc/formations/#{formation_id}/deploy", payload)
    end

    def update_formation(formation_id, payload)
      rpc_post("/rpc/formations/#{formation_id}/update", payload)
    end

    def get_formation_logs(formation_id, limit: nil)
      params = limit ? { limit: limit } : nil
      rpc_get("/rpc/formations/#{formation_id}/logs", params: params)
    end

    def get_server_logs(limit: nil)
      params = limit ? { limit: limit } : nil
      rpc_get("/rpc/server/logs", params: params)
    end

    # Streaming
    def deploy_formation_stream(formation_id, payload, &block)
      stream_sse("/rpc/formations/#{formation_id}/deploy/stream", body: payload, &block)
    end

    def update_formation_stream(formation_id, payload, &block)
      stream_sse("/rpc/formations/#{formation_id}/update/stream", body: payload, &block)
    end

    def start_formation_stream(formation_id, &block)
      stream_sse("/rpc/formations/#{formation_id}/start/stream", body: {}, &block)
    end

    def restart_formation_stream(formation_id, &block)
      stream_sse("/rpc/formations/#{formation_id}/restart/stream", body: {}, &block)
    end

    def rollback_formation_stream(formation_id, &block)
      stream_sse("/rpc/formations/#{formation_id}/rollback/stream", body: {}, &block)
    end

    def stream_formation_logs(formation_id, &block)
      stream_sse("/rpc/formations/#{formation_id}/logs/stream", &block)
    end

    private

    def rpc_get(path, params: nil)
      @transport.request_json("GET", path, params: params)
    end

    def rpc_post(path, body)
      @transport.request_json("POST", path, body: body)
    end

    def rpc_delete(path)
      @transport.request_json("DELETE", path)
    end

    def stream_sse(path, body: nil, &block)
      return enum_for(:stream_sse, path, body: body) unless block_given?

      event = nil
      data_parts = []

      @transport.stream_lines("POST", path, body: body) do |line|
        line = line.chomp
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
