# frozen_string_literal: true

module Muxi
  class MuxiError < StandardError
    attr_reader :code, :status_code, :details

    def initialize(code, message, status_code, details = nil)
      @code = code
      @status_code = status_code
      @details = details || {}
      super(code ? "#{code}: #{message}" : message)
    end
  end

  class AuthenticationError < MuxiError; end
  class AuthorizationError < MuxiError; end
  class NotFoundError < MuxiError; end
  class ConflictError < MuxiError; end
  class ValidationError < MuxiError; end

  class RateLimitError < MuxiError
    attr_reader :retry_after

    def initialize(message, status_code, retry_after: nil, details: nil)
      super("RATE_LIMITED", message, status_code, details)
      @retry_after = retry_after
    end
  end

  class ServerError < MuxiError; end
  class ConnectionError < MuxiError; end

  class << self
    def map_error(status, code, message, details = nil, retry_after = nil)
      case status
      when 401
        AuthenticationError.new(code || "UNAUTHORIZED", message, status, details)
      when 403
        AuthorizationError.new(code || "FORBIDDEN", message, status, details)
      when 404
        NotFoundError.new(code || "NOT_FOUND", message, status, details)
      when 409
        ConflictError.new(code || "CONFLICT", message, status, details)
      when 422
        ValidationError.new(code || "VALIDATION_ERROR", message, status, details)
      when 429
        RateLimitError.new(message || "Too Many Requests", status, retry_after: retry_after, details: details)
      when 500..599
        ServerError.new(code || "SERVER_ERROR", message, status, details)
      else
        MuxiError.new(code || "ERROR", message, status, details)
      end
    end
  end
end
