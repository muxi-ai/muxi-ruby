# frozen_string_literal: true

require "spec_helper"

RSpec.describe Muxi::FormationTransport do
  subject(:transport) do
    described_class.new(
      base_url: "http://example.com",
      admin_key: "admin-key",
      client_key: "client-key",
      timeout: 30,
      max_retries: 0,
      debug: false,
      logger: Logger.new(nil)
    )
  end

  it "flushes event-only done frames" do
    event = "done"
    data_parts = []

    parsed = transport.send(:flush_sse_event, event, data_parts)

    expect(parsed).to eq({ "event" => "done", "data" => "" })
  end

  it "preserves multiline data" do
    parsed = transport.send(:flush_sse_event, "planning", %w[one two])

    expect(parsed).to eq({ "event" => "planning", "data" => "one\ntwo" })
  end

  it "raises on route-level error events" do
    expect do
      transport.send(:throw_if_route_error, { "event" => "error", "data" => '{"error":"boom","type":"RUNTIME_ERROR"}' })
    end.to raise_error(Muxi::MuxiError, "RUNTIME_ERROR: boom")
  end
end
