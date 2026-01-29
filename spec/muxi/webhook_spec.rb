# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Muxi::Webhook do
  let(:secret) { "test_webhook_secret" }
  let(:payload) { '{"id":"req123","status":"completed","response":[{"type":"text","text":"Hello"}]}' }

  describe ".verify_signature" do
    def create_signature(payload, secret, timestamp = Time.now.to_i)
      message = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, message)
      "t=#{timestamp},v1=#{signature}"
    end

    it "returns true for valid signature" do
      timestamp = Time.now.to_i
      sig_header = create_signature(payload, secret, timestamp)
      
      expect(described_class.verify_signature(payload, sig_header, secret)).to be true
    end

    it "returns false for invalid signature" do
      sig_header = "t=#{Time.now.to_i},v1=invalidsignature"
      
      expect(described_class.verify_signature(payload, sig_header, secret)).to be false
    end

    it "returns false for nil signature header" do
      expect(described_class.verify_signature(payload, nil, secret)).to be false
    end

    it "returns false for empty signature header" do
      expect(described_class.verify_signature(payload, "", secret)).to be false
    end

    it "returns false for expired timestamp" do
      old_timestamp = Time.now.to_i - 600 # 10 minutes ago
      sig_header = create_signature(payload, secret, old_timestamp)
      
      expect(described_class.verify_signature(payload, sig_header, secret)).to be false
    end

    it "raises error for missing secret" do
      sig_header = create_signature(payload, secret)
      
      expect { described_class.verify_signature(payload, sig_header, nil) }
        .to raise_error(Muxi::Webhook::VerificationError, "Webhook secret is required")
    end
  end

  describe ".parse" do
    it "parses a completed webhook payload" do
      event = described_class.parse(payload)
      
      expect(event.request_id).to eq("req123")
      expect(event.status).to eq("completed")
      expect(event.content.length).to eq(1)
      expect(event.content.first.type).to eq("text")
      expect(event.content.first.text).to eq("Hello")
    end

    it "parses a failed webhook payload" do
      failed_payload = {
        "id" => "req456",
        "status" => "failed",
        "error" => { "code" => "TIMEOUT", "message" => "Request timed out" }
      }
      
      event = described_class.parse(failed_payload)
      
      expect(event.status).to eq("failed")
      expect(event.error).not_to be_nil
      expect(event.error.code).to eq("TIMEOUT")
      expect(event.error.message).to eq("Request timed out")
    end

    it "parses a clarification webhook payload" do
      clarification_payload = {
        "id" => "req789",
        "status" => "awaiting_clarification",
        "clarification_question" => "Which file do you mean?"
      }
      
      event = described_class.parse(clarification_payload)
      
      expect(event.status).to eq("awaiting_clarification")
      expect(event.clarification).not_to be_nil
      expect(event.clarification.question).to eq("Which file do you mean?")
    end

    it "accepts hash input" do
      event = described_class.parse(JSON.parse(payload))
      expect(event.request_id).to eq("req123")
    end

    it "raises error for invalid JSON" do
      expect { described_class.parse("not json") }
        .to raise_error(Muxi::Webhook::VerificationError, /Invalid JSON payload/)
    end
  end
end
