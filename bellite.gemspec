# -*- encoding: utf-8 -*-
require File.expand_path('../lib/bellite/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Shane Holloway"]
  gem.email         = ["shane@techgame.net"]
  gem.description   = "Bellite JSON-RPC Client library"
  gem.summary       = "Implements connection to JSON-RPC server, calling remote methods and bindings to server events"
  gem.homepage      = "https://github.com/bellite/bellite-ruby"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "bellite"
  gem.require_paths = ["lib"]
  gem.version       = Bellite::VERSION
  gem.license       = 'MIT'


  gem.add_development_dependency "redcarpet", "~> 1.17"
  gem.add_development_dependency "yard", "~> 0.7.5"
  gem.add_dependency "json"
end
