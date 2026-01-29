# frozen_string_literal: true

require "openssl"
require "base64"

module Muxi
  module Auth
    module_function

    def generate_hmac_signature(secret_key, method, path)
      timestamp = Time.now.to_i
      sign_path = path.split("?").first
      message = "#{timestamp};#{method};#{sign_path}"
      
      digest = OpenSSL::Digest.new("sha256")
      hmac = OpenSSL::HMAC.digest(digest, secret_key, message)
      signature = Base64.strict_encode64(hmac)
      
      [signature, timestamp]
    end

    def build_auth_header(key_id, secret_key, method, path)
      signature, timestamp = generate_hmac_signature(secret_key, method, path)
      "MUXI-HMAC key=#{key_id}, timestamp=#{timestamp}, signature=#{signature}"
    end
  end
end
