require 'rubygems'

SPEC = Gem::Specification.new do |s|
  s.name = 'protostruct'
  s.summary = 'A ruby protocol serialization and parsing engine, with bit-struct style protocol definitions'
  s.version = '0.1.0'
  s.author = 'Ryan Blue'
  s.email = 'rdblue@gmail.com'
  s.homepage = 'http://protostruct.rubyforge.org'
  s.rubyforge_project = 'protostruct'
  s.files = Dir.glob( 'bin/*.rb' ) + Dir.glob( 'lib/**/*.rb' ) +
            ['test/protostruct_test.rb']
  s.test_file = 'test/protostruct_test.rb'
  s.has_rdoc = true
  s.extra_rdoc_files = ['README', 'LICENSE']
end
