# frozen_string_literal: true

require_relative "lib/muxi/version"

Gem::Specification.new do |spec|
  spec.name = "muxi"
  spec.version = Muxi::VERSION
  spec.authors = ["MUXI AI"]
  spec.email = ["support@muxi.ai"]

  spec.summary = "MUXI Ruby SDK"
  spec.description = "Ruby SDK for MUXI AI platform - manage AI agent formations and interact with their runtime APIs"
  spec.homepage = "https://github.com/muxi-ai/muxi-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/muxi-ai/muxi-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/muxi-ai/muxi-ruby/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies - minimal, stdlib only
  # Net::HTTP, JSON, OpenSSL, SecureRandom are stdlib

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
