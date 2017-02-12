require 'json'

# USEFUL PROPERTIES
# first_name
# last_name
# birthday
# grade_level
# graduation_year
# advisor
# address
# email

module Veracross
	def initialize(config)
		path_to_data = config['veracross']['path']
		@data = JSON.load(File.read(path_to_data))
	end
	
	
end