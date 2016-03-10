# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "nrms"
  spec.version       = '1.0'
  spec.authors       = ["Frank Matranga"]
  spec.email         = ["thefrankmatranga@gmail.com"]
  spec.summary       = %q{Regis Moodle scraper}
  spec.description   = %q{Regis Moodle scraper}
  spec.homepage      = "https://github.com/Aedificem/nrms"
  spec.license       = "MIT"

  spec.files         = ['lib/nrms.rb']
  spec.executables   = ['bin/nrms']
  spec.test_files    = ['tests/test_nrms.rb']
  spec.require_paths = ["lib"]
end
