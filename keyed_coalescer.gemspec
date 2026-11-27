# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "keyed_coalescer"
  spec.version = "0.1.0"
  spec.authors = ["Small Primitives"]
  spec.summary = "Share the result of overlapping Ruby calls by key"
  spec.homepage = "https://github.com/smallprimitives/keyed_coalescer"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.files = ["LICENSE-MIT", "README.md", "lib/keyed_coalescer.rb"]
  spec.require_paths = ["lib"]
end
