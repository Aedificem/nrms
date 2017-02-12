require 'mechanize'
require 'pry'

class Scraper
  include Database
	
	def get_student(username_or_email)
		username_or_email += "@regis.org" unless username_or_email.end_with? "@regis.org"
		@data.find { |entry| entry['email'] = username_or_email }
	end
	
  def initialize(config)
    @config = config
    @agent = Mechanize.new
		
		path_to_data = config['veracross']['path']
		@data = JSON.load(File.read(path_to_data))
		
    @grades = {
    	"1" => 19,
    	"2" => 18,
    	"3" => 17,
    	"4" => 16
    }

    super(config)
  end

  def login
    page = @agent.post('https://moodle.regis.org/login/index.php', {
    	"username" => @config["auth"]["regis"]["username"],
    	"password" => @config["auth"]["regis"]["password"],
    })

    if page.title != "Dashboard"
      return false
    end

    return true
  end
	
	def loop
		# This page has ALL teachers/staff/students on one page with links to each
		index_url = 'http://moodle.regis.org/user/index.php?contextid=2&roleid=0&id=1&perpage=5000&accesssince=0&search&ssort=department'
		page = @agent.get(index_url)
		
		page.search('//table[@id = "participants"]/tbody/tr').each do |row|
			cells = row.search('td')
			# PICTURE  |  NAME  | DEPARTMENT
			url = cells[1].search('a').first['href'].split('&course=1')[0]
			
			department = cells[2].text
			
			html = @agent.get(url)
			mid = Integer(url.split("id=")[1])
			
			if department.empty? or %w(1 2 3 4).include? department[0]
				# PERSON
				begin
					extract_person(mid, html)
				rescue InvalidPage => e
					puts "INVALID PERSON: "
					puts e
					@client.query("DELETE FROM staffs WHERE id=#{mid}")
					@client.query("DELETE FROM students WHERE id=#{mid}")
				end
			else
				# STAFF MEMBER
				@client.query("DELETE FROM courses WHERE id=#{mid}")
				begin
					extract_course(mid, html)
				rescue => e
					puts e
				end
			end

			sleep 1
		end
	end
	
  def scrape(type)
		if type == "people"
			loop
			return
		end
		
		return
    base_url = "http://moodle.regis.org/course/view.php?id="

    from = @config["options"][type]["from"]
    to = @config["options"][type]["to"]

    (from..to).each do |i|
    	if not @config["ignores"][type].include? i
    		sleep(1)
    		begin
    			page = @agent.get(base_url + i.to_s)
    			if page.title == "Notice" or page.title == "Error" or !page.title or page.title.include? "Test" or page.title.include? "Parent" or page.title.include? "Nurse"
						@client.query("DELETE FROM courses WHERE id=#{i}")
            
            @config["ignores"][type].push(i)
            puts "Skipped #{i}"
            next
    			end

					extract_course(i, page)
    		rescue Mechanize::ResponseCodeError
    			@config["ignores"][type].push(i)
          puts "Skipped #{i}"
    			next
    		end
      else
        puts "Skipped #{i}"
    	end
    end
  end

  def extract_person(mid, page)
  	name = page.title.split(":")[0].split(" ")
  	first_name = name[0]
  	last_name = name[1...10].join(" ")
		
		raise InvalidPage, 'Student test account.' if [first_name, last_name].include? 'Student'
		raise InvalidPage, 'Test account.' if [first_name, last_name].include? 'Test'
		
		raise InvalidPage, 'Name is only one word.' if first_name.empty? or last_name.empty?
		
		username = nil
		
  	begin
			picture = page.search("a/img[@alt=\"Picture of #{first_name} #{last_name}\"]")[0]['src']
  	rescue
			puts "Failed to get image of person with MID #{mid}"
			raise InvalidPage
		end
		type = :staff

  	department = page.search("//dd[../dt = 'Department']/text()").to_s
  	if /\A\d+\z/.match(department[0]) or department.empty?
			# GET TRUE INFO FROM VERACROSS JSON
			username = (first_name[0] + last_name).downcase.sub("'", '').sub('-', '').sub(' ', '')
  		advisor = get_student(username)
			raise InvalidPage, "Failed to create username. #{username} is wrong." if advisor.nil?
			advisor = advisor['advisor']
			
			result = @client.query("SELECT staffs.last_name, courses.title FROM courses JOIN staffs ON staffs.id = courses.teacher_id WHERE courses.title LIKE \"Advisement%\" AND staffs.last_name='#{advisor}'").first
			raise "Failed to find advisement from Veracross for #{username}." if result.nil?
			
			department = result['title'].split('Advisement ')[1]
			
			type = :student
  	end

  	puts "#{mid.to_s}: #{type.capitalize} #{last_name}, #{first_name} of #{department}"

  	if type == :staff
  		sql = "INSERT INTO staffs (id, username, first_name, last_name, department, mpicture) VALUES(#{mid}, \"#{username}\", \"#{first_name}\", \"#{last_name}\", \"#{department}\", \"#{picture}\")"
  		sql += " ON DUPLICATE KEY UPDATE username=\"#{username}\", first_name=\"#{first_name}\", last_name=\"#{last_name}\", department=\"#{department}\", mpicture=\"#{picture}\""
  		@client.query(sql)
  	else
  		grade =  @grades[department[0]]
  		
			sql = "INSERT INTO students (id, username, first_name, last_name, advisement, mpicture) VALUES(#{mid}, \"#{username}\", \"#{first_name}\", \"#{last_name}\", \"#{department}\", \"#{picture}\")"
  		sql += " ON DUPLICATE KEY UPDATE username=\"#{username}\", first_name=\"#{first_name}\", last_name=\"#{last_name}\", advisement=\"#{department}\", mpicture=\"#{picture}\""
  		@client.query(sql)

  		@client.query("DELETE FROM students_courses WHERE student_id=#{mid}")
  		page.search("//dd/ul/li/a[contains(@href, 'http://moodle.regis.org/course/view.php?id=')]").each do |link|
  			cid = link["href"].split("id=")[1].split("&")[0]
  			sql = "INSERT INTO students_courses (student_id, course_id) VALUES (#{mid}, #{cid})"
  			@client.query(sql)
  		end
  	end
  end

  def extract_course(mid, page)
  	parts = page.title.split(":")
  	#puts parts
    is_class = (parts.length > 2)
    #puts is_class
    
  	title = parts[1]
  	if parts.length == 1
  		title = parts[0]
  	end

  	title.strip!

  	teacher_page = @agent.get("http://moodle.regis.org/user/index.php?roleid=3&sifirst=&silast=&id="+mid.to_s)

  	teacher_id = nil
  	begin
  		teacher_id = teacher_page.search("//strong/a[contains(@href, 'moodle.regis.org')]")[0]['href'].split("?id=")[1].split("&course=")[0].to_i
  	rescue NoMethodError

  	end

  	puts mid.to_s + ": " + title
  	title = @client.escape(title)
  	t_id = "NULL"
  	t_id2 = ""
  	if teacher_id
  		t_id = teacher_id
  		t_id2 = "teacher_id=#{teacher_id}, "
  	end

  	sql = "INSERT INTO courses (id, teacher_id, title, is_class) VALUES(#{mid}, #{t_id}, '#{title}', #{is_class}) ON DUPLICATE KEY UPDATE #{t_id2}title='#{title}', is_class= #{is_class}"
  	@client.query(sql)
  end

  def finish
    File.open('./data/config.yaml', 'w') { |f| f.puts @config.to_yaml }
    puts "Updated config.yaml"
  end
end
