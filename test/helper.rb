require 'codeclimate-test-reporter'
CodeClimate::TestReporter.start

require 'minitest/autorun'
require 'tilt/redcarpet'
require 'tilt/erubis'
require 'dimples'

def test_site
  @site ||= Dimples::Site.new({
    'source_path' => File.join(__dir__, 'site'),
    'destination_path' => File.join(__dir__, 'build')
  })
end