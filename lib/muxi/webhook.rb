# frozen_string_literal: true

require "openssl"
require "json"

module Muxi
  module Webhook
    class VerificationError < StandardError
      attr_reader :message

      def initialize(message)
        @message = message
        super(message)
      end
    end

    ContentItem = Struct.new(:type, :text, :file, keyword_init: true) do
      def self.from_hash(data)
        new(
          type: data["type"] || "text",
          text: data["text"],
          file: data["file"]
        )
      end
    end

    ErrorDetails = Struct.new(:code, :message, :trace, keyword_init: true) do
      def self.from_hash(data)
        new(
          code: data["code"] || "unknown",
          message: data["message"] || "Unknown error",
          trace: data["trace"]
        )
      end
    end

    Clarification = Struct.new(:question, :clarification_request_id, :original_message, keyword_init: true) do
      def self.from_hash(data)
        new(
          question: data["clarification_question"] || "",
          clarification_request_id: data["clarification_request_id"],
          original_message: data["original_message"]
        )
      end
    end

    WebhookEvent = Struct.new(
      :request_id, :status, :timestamp, :content, :error, :clarification,
      :formation_id, :user_id, :processing_time, :processing_mode, :webhook_url, :raw,
      keyword_init: true
    ) do
      def self.from_hash(data)
        content = (data["response"] || []).map { |item| ContentItem.from_hash(item) }
        error = data["error"] ? ErrorDetails.from_hash(data["error"]) : nil
        clarification = data["status"] == "awaiting_clarification" ? Clarification.from_hash(data) : nil

        new(
          request_id: data["id"] || "",
          status: data["status"] || "unknown",
          timestamp: data["timestamp"] || 0,
          content: content,
          error: error,
          clarification: clarification,
          formation_id: data["formation_id"],
          user_id: data["user_id"],
          processing_time: data["processing_time"],
          processing_mode: data["processing_mode"] || "async",
          webhook_url: data["webhook_url"],
          raw: data
        )
      end
    end

    module_function

    def verify_signature(payload, signature_header, secret, tolerance_seconds: 300)
      return false if signature_header.nil? || signature_header.empty?
      raise VerificationError, "Webhook secret is required" if secret.nil? || secret.empty?

      # Parse signature header: "t=1234567890,v1=abc123..."
      begin
        parts = signature_header.split(",").map { |p| p.split("=", 2) }.to_h
        timestamp_str = parts["t"]
        signature = parts["v1"]

        return false if timestamp_str.nil? || signature.nil?

        timestamp = timestamp_str.to_i
      rescue StandardError
        return false
      end

      # Check timestamp tolerance
      current_time = Time.now.to_i
      return false if (current_time - timestamp).abs > tolerance_seconds

      # Normalize payload
      payload_bytes = payload.is_a?(String) ? payload : payload.to_s

      # Compute expected signature
      message = "#{timestamp}.#{payload_bytes}"
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, message)

      # Constant-time comparison
      secure_compare(expected, signature)
    end

    def parse(payload)
      data = case payload
             when Hash
               payload
             when String
               begin
                 JSON.parse(payload)
               rescue JSON::ParserError => e
                 raise VerificationError, "Invalid JSON payload: #{e.message}"
               end
             else
               raise VerificationError, "Unsupported payload type: #{payload.class}"
             end

      WebhookEvent.from_hash(data)
    end

    def secure_compare(a, b)
      return false if a.nil? || b.nil?
      return false if a.bytesize != b.bytesize

      l = a.unpack("C*")
      r = 0
      b.each_byte { |v| r |= v ^ l.shift }
      r == 0
    end
  end
end
