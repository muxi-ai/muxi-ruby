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

  it "unwraps the echoed idempotency_key" do
    env = {
      "object" => "api_response",
      "timestamp" => 123,
      "request" => { "id" => "req-1", "idempotency_key" => "idem-42" },
      "data" => { "foo" => "bar" },
      "success" => true
    }

    out = transport.send(:unwrap_envelope, env)

    expect(out["foo"]).to eq("bar")
    expect(out["request_id"]).to eq("req-1")
    expect(out["idempotency_key"]).to eq("idem-42")
  end

  it "omits idempotency_key when not echoed" do
    env = {
      "object" => "api_response",
      "request" => { "id" => "req-1" },
      "data" => { "foo" => "bar" },
      "success" => true
    }

    out = transport.send(:unwrap_envelope, env)

    expect(out).not_to have_key("idempotency_key")
  end
end

RSpec.describe "Muxi.parse_ui_widgets" do
  it "parses widgets from a ui frame" do
    event = {
      "event" => "ui",
      "data" => '{"ui":[{"type":"options","id":"w1","prompt":"Which?",' \
                '"options":[{"value":"us","label":"United States"}]},' \
                '{"type":"action_link","id":"w2","label":"Dash","url":"https://x.io"}]}'
    }

    widgets = Muxi.parse_ui_widgets(event)

    expect(widgets.length).to eq(2)
    expect(widgets[0]["type"]).to eq("options")
    expect(widgets[0]["options"][0]["label"]).to eq("United States")
    expect(widgets[1]["url"]).to eq("https://x.io")
  end

  it "returns [] for non-ui and malformed frames" do
    expect(Muxi.parse_ui_widgets({ "event" => "message", "data" => "hi" })).to eq([])
    expect(Muxi.parse_ui_widgets({ "event" => "ui", "data" => "not json" })).to eq([])
    expect(Muxi.parse_ui_widgets({ "event" => "ui", "data" => '{"ui":{}}' })).to eq([])
  end
end
