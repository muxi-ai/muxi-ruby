# frozen_string_literal: true

require "json"
require "fileutils"

module Muxi
  module VersionCheck
    SDK_NAME = "ruby"
    CACHE_FILE = File.join(Dir.home, ".muxi", "sdk-versions.json")
    TWELVE_HOURS = 12 * 60 * 60

    @checked = false

    class << self
      def check_for_updates(headers)
        return if @checked
        @checked = true

        return if ENV["MUXI_SDK_VERSION_NOTIFICATION"] == "0"

        latest = headers["X-Muxi-SDK-Latest"] || headers["x-muxi-sdk-latest"]
        return unless latest

        return unless newer_version?(latest, VERSION)

        update_latest_version(latest)

        unless notified_recently?
          puts "[muxi] SDK update available: #{latest} (current: #{VERSION})"
          puts "[muxi] Run: gem update muxi"
          mark_notified
        end
      end

      private

      def newer_version?(latest, current)
        latest > current
      end

      def load_cache
        return {} unless File.exist?(CACHE_FILE)
        JSON.parse(File.read(CACHE_FILE))
      rescue
        {}
      end

      def save_cache(cache)
        FileUtils.mkdir_p(File.dirname(CACHE_FILE))
        File.write(CACHE_FILE, JSON.pretty_generate(cache))
      rescue
        # Ignore cache errors
      end

      def notified_recently?
        cache = load_cache
        entry = cache[SDK_NAME]
        return false unless entry && entry["last_notified"]

        last_notified = Time.parse(entry["last_notified"])
        Time.now - last_notified < TWELVE_HOURS
      rescue
        false
      end

      def update_latest_version(latest)
        cache = load_cache
        entry = cache[SDK_NAME] || {}
        cache[SDK_NAME] = entry.merge(
          "current" => VERSION,
          "latest" => latest
        )
        save_cache(cache)
      end

      def mark_notified
        cache = load_cache
        if cache[SDK_NAME]
          cache[SDK_NAME]["last_notified"] = Time.now.iso8601
          save_cache(cache)
        end
      end
    end
  end
end
