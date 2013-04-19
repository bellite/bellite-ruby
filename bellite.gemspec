# -*- encoding: utf-8 -*-
require File.expand_path('../lib/bellite/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Shane Holloway"]
  gem.email         = ["shane@bellite.io"]
  gem.description   = "Bellite JSON-RPC client library"
  gem.summary       = "Create desktop applications for Mac OSX (10.7 & 10.8) and Windows XP, 7 & 8 using modern web technology and Ruby (Python or Node.js or PHP or Java)."
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
