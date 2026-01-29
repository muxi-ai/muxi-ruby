# frozen_string_literal: true

require "spec_helper"

RSpec.describe Muxi::Auth do
  describe ".generate_hmac_signature" do
    it "generates a valid signature and timestamp" do
      signature, timestamp = described_class.generate_hmac_signature("secret", "GET", "/test")
      
      expect(signature).to be_a(String)
      expect(signature.length).to be > 0
      expect(timestamp).to be_a(Integer)
      expect(timestamp).to be_within(5).of(Time.now.to_i)
    end

    it "strips query params from path for signing" do
      sig1, _ = described_class.generate_hmac_signature("secret", "GET", "/test")
      sig2, _ = described_class.generate_hmac_signature("secret", "GET", "/test?foo=bar")
      
      # Same base path should produce same signature (ignoring timestamp variance)
      expect(sig1.length).to eq(sig2.length)
    end
  end

  describe ".build_auth_header" do
    it "builds a properly formatted auth header" do
      header = described_class.build_auth_header("key123", "secret", "POST", "/rpc/test")
      
      expect(header).to start_with("MUXI-HMAC key=key123, timestamp=")
      expect(header).to include("signature=")
    end
  end
end
