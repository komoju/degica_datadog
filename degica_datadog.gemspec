# frozen_string_literal: true

require_relative "lib/degica_datadog/version"

Gem::Specification.new do |spec|
  spec.name = "degica_datadog"
  spec.version = DegicaDatadog::VERSION
  spec.authors = ["Robin Schroer"]
  spec.email = ["git@sulami.xyz"]

  spec.summary = "Datadog statsd & tracing utitlities for Degica services"
  spec.homepage = "https://github.com/degica/degica_datadog"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "datadog", "~> 2"
  spec.add_dependency "datadog_api_client", "~> 2"
  spec.add_dependency "datadog-ci", "~> 1"
  spec.add_dependency "dogstatsd-ruby", "~> 5"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "simplecov-cobertura"
end
