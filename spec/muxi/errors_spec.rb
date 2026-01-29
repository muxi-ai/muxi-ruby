# frozen_string_literal: true

require "spec_helper"

RSpec.describe Muxi do
  describe ".map_error" do
    it "maps 401 to AuthenticationError" do
      error = described_class.map_error(401, "INVALID_KEY", "Invalid API key")
      
      expect(error).to be_a(Muxi::AuthenticationError)
      expect(error.status_code).to eq(401)
      expect(error.code).to eq("INVALID_KEY")
    end

    it "maps 403 to AuthorizationError" do
      error = described_class.map_error(403, "FORBIDDEN", "Access denied")
      
      expect(error).to be_a(Muxi::AuthorizationError)
      expect(error.status_code).to eq(403)
    end

    it "maps 404 to NotFoundError" do
      error = described_class.map_error(404, "NOT_FOUND", "Resource not found")
      
      expect(error).to be_a(Muxi::NotFoundError)
      expect(error.status_code).to eq(404)
    end

    it "maps 409 to ConflictError" do
      error = described_class.map_error(409, "CONFLICT", "Already exists")
      
      expect(error).to be_a(Muxi::ConflictError)
      expect(error.status_code).to eq(409)
    end

    it "maps 422 to ValidationError" do
      error = described_class.map_error(422, "VALIDATION_ERROR", "Invalid input")
      
      expect(error).to be_a(Muxi::ValidationError)
      expect(error.status_code).to eq(422)
    end

    it "maps 429 to RateLimitError with retry_after" do
      error = described_class.map_error(429, nil, "Rate limited", nil, 60)
      
      expect(error).to be_a(Muxi::RateLimitError)
      expect(error.status_code).to eq(429)
      expect(error.retry_after).to eq(60)
    end

    it "maps 5xx to ServerError" do
      error = described_class.map_error(500, "INTERNAL", "Server error")
      
      expect(error).to be_a(Muxi::ServerError)
      expect(error.status_code).to eq(500)
    end

    it "maps unknown status to MuxiError" do
      error = described_class.map_error(418, "TEAPOT", "I'm a teapot")
      
      expect(error).to be_a(Muxi::MuxiError)
      expect(error).not_to be_a(Muxi::AuthenticationError)
    end
  end
end
