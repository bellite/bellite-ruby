# -*- encoding: utf-8 -*-
require File.expand_path('../lib/bellite/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Ivan"]
  gem.email         = ["asmer@asmer.org.ua"]
  gem.description   = "Bellite JSON-RPC Client library"
  gem.summary       = "Implements connection to JSON-RPC server, calling remote methods and bindings to server events"
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "bellite"
  gem.require_paths = ["lib"]
  gem.version       = Bellite::VERSION


  gem.add_development_dependency "redcarpet", "~> 1.17"
  gem.add_development_dependency "yard", "~> 0.7.5"
end
