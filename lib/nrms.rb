require 'yaml'
require_relative 'nrms/db'
require_relative 'nrms/scraper'

CONFIG = YAML::load_file('./data/config.yaml')

start_time = Time.now
puts "STARTING #{start_time.strftime("%Y-%m-%d %H:%M:%S")}"
puts "-"*30
puts "\n"

scraper = Scraper.new CONFIG
if scraper.login
  puts "Logged in!"
  begin
    scraper.scrape "courses"
    scraper.scrape "people"
  rescue Exception => e
    puts e
  ensure
    scraper.finish
  end
else
  puts "Failed to login. Exiting..."
  exit 1
end

end_time = Time.now

puts "\n"
puts "-"*30
puts "FINISHED #{end_time.strftime("%Y-%m-%d %H:%M:%S")}"
puts "\n"
puts "Time elapsed #{(end_time - start_time)} seconds"
