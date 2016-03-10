require 'yaml'
require './lib/nrms/db'
require "./lib/nrms/scraper"
require "test/unit"

class TestScraper < Test::Unit::TestCase
  def test_good_login()
    config = YAML::load_file('./data/config.yaml')
    scraper = Scraper.new config

    assert(scraper.login, 'Failed to login with correct credentials!')
  end

  def test_bad_login()
    config = YAML::load_file('./data/config.yaml')
    config["auth"]["regis"]["password"] = "badpassword"
    scraper = Scraper.new config

    assert(!scraper.login, 'Somehow logged in with incorrect credentials!')
  end
end
