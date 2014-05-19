# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'thumbnail_optimization/version'

Gem::Specification.new do |spec|
  spec.name          = "thumbnail_optimization"
  spec.version       = ThumbnailOptimization::VERSION
  spec.authors       = ["Tali Petrover"]
  spec.email         = ["atalyad@gmail.com"]
  spec.summary       = %q{Run thumbs A/B tests}
  spec.description   = %q{Run thumbs A/B tests}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'redis',           '>= 2.1'
  spec.add_dependency 'redis-namespace', '>= 1.1.0'
  spec.add_dependency 'paperclip',       '~> 3.4.2'
  spec.add_dependency 'sinatra',         '>= 1.2.6'
  spec.add_dependency 'jquery-fileupload-rails'


  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
end
