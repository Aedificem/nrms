require 'mechanize'

class Scraper
  include Database

  def initialize(config)
    @config = config
    @agent = Mechanize.new

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

  def scrape(type)
    base_url = "http://moodle.regis.org/course/view.php?id="
    if type == "people"
      base_url = "http://moodle.regis.org/user/profile.php?id="
    end

    from = @config["options"][type]["from"]
    to = @config["options"][type]["to"]

    (from..to).each do |i|
    	if not @config["ignores"][type].include? i
    		sleep(1)
    		begin
    			page = @agent.get(base_url + i.to_s)
    			if page.title == "Notice" or page.title == "Error" or !page.title or page.title.include? "Test" or page.title.include? "Parent" or page.title.include? "Nurse"

            if type == "people"
              @client.query("DELETE FROM staffs WHERE id=#{i}")
      				@client.query("DELETE FROM students WHERE id=#{i}")
            else
              @client.query("DELETE FROM courses WHERE id=#{i}")
            end

            @config["ignores"][type].push(i)
            puts "Skipped #{i}"
            next
    			end

          if type == "courses"
            extract_course(i, page)
          else
            extract_person(i, page)
          end
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
	
  	picture = page.search("a/img[@alt=\"Picture of #{first_name} #{last_name}\"]")[0]['src']
  	type = :staff

  	department = page.search("//dd[../dt = 'Department']/text()").to_s
  	if /\A\d+\z/.match(department[0])
  		type = :student
  	end

  	puts "#{mid.to_s}: #{type.capitalize} #{last_name}, #{first_name} of #{department}"

  	if type == :staff
  		username = (first_name[0] + last_name).downcase.sub("'", "")
  		sql = "INSERT INTO staffs (id, username, first_name, last_name, department, mpicture) VALUES(#{mid}, \"#{username}\", \"#{first_name}\", \"#{last_name}\", \"#{department}\", \"#{picture}\")"
  		sql += " ON DUPLICATE KEY UPDATE username=\"#{username}\", first_name=\"#{first_name}\", last_name=\"#{last_name}\", department=\"#{department}\", mpicture=\"#{picture}\""
  		@client.query(sql)
  	else
  		grade =  @grades[department[0]]
  		username = (first_name[0] + last_name + grade.to_s).downcase.sub("'", "").sub("-", "")
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

  	sql = "INSERT INTO courses (id, teacher_id, title) VALUES(#{mid}, #{t_id}, '#{title}') ON DUPLICATE KEY UPDATE #{t_id2}title='#{title}'"
  	@client.query(sql)
  end

  def finish
    File.open('./data/config.yaml', 'w') { |f| f.puts @config.to_yaml }
    puts "Updated config.yaml"
  end
end
