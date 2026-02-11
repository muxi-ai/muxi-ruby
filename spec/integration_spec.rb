# frozen_string_literal: true

require "spec_helper"
require "muxi"

RSpec.describe "Integration Tests", :integration do
  def env!(name)
    ENV[name] || skip("#{name} not set")
  end

  let(:server_url) { env!("MUXI_SDK_E2E_SERVER_URL") }
  let(:key_id) { env!("MUXI_SDK_E2E_KEY_ID") }
  let(:secret_key) { env!("MUXI_SDK_E2E_SECRET_KEY") }
  let(:formation_id) { env!("MUXI_SDK_E2E_FORMATION_ID") }
  let(:client_key) { env!("MUXI_SDK_E2E_CLIENT_KEY") }
  let(:admin_key) { env!("MUXI_SDK_E2E_ADMIN_KEY") }

  let(:server) do
    Muxi::ServerClient.new(
      url: server_url,
      key_id: key_id,
      secret_key: secret_key
    )
  end

  let(:formation) do
    Muxi::FormationClient.new(
      server_url: server_url,
      formation_id: formation_id,
      client_key: client_key,
      admin_key: admin_key
    )
  end

  describe "ServerClient" do
    it "ping returns pong" do
      result = server.ping
      expect(result).to be >= 0
    end

    it "health returns status" do
      result = server.health
      expect(result).to be_a(Hash)
    end

    it "status returns server info" do
      result = server.status
      expect(result).to be_a(Hash)
    end

    it "list_formations returns formations" do
      result = server.list_formations
      expect(result).to be_a(Hash)
    end
  end

  describe "FormationClient" do
    it "health returns status" do
      result = formation.health
      expect(result).to be_a(Hash)
    end

    it "get_status returns formation status" do
      result = formation.get_status
      expect(result).to be_a(Hash)
    end

    it "get_config returns configuration" do
      result = formation.get_config
      expect(result).to be_a(Hash)
    end

    it "get_agents returns agents list" do
      result = formation.get_agents
      expect(result).to be_a(Hash)
    end
  end
end
