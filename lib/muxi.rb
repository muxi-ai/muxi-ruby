# frozen_string_literal: true

require_relative "muxi/version"
require_relative "muxi/errors"
require_relative "muxi/auth"
require_relative "muxi/version_check"
require_relative "muxi/transport"
require_relative "muxi/server_client"
require_relative "muxi/formation_client"
require_relative "muxi/webhook"

module Muxi
  class << self
    attr_accessor :debug

    def debug?
      @debug || ENV["MUXI_DEBUG"] == "1"
    end
  end
end
