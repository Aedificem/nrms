#!/usr/bin/env ruby -w

require 'mechanize'
require 'mysql2'
require 'json'

path = "secrets.json"
if ARGV[0]
	path = ARGV[0]
end
secrets = JSON.parse(File.read(path))

@agent = Mechanize.new

USERNAME = secrets['REGIS_USERNAME']
PASSWORD = secrets['REGIS_PASSWORD']

if !USERNAME or !PASSWORD
	puts "Did not pass credentials!"
	exit
end

page = @agent.post('https://moodle.regis.org/login/index.php', {
	"username" => USERNAME,
	"password" => PASSWORD,
})

if page.title != "Dashboard"
	puts "Failed to login!"
	exit
end

@client = Mysql2::Client.new(:host => secrets['DB_HOST'], :username => secrets['DB_USER'], :password => secrets['DB_PASSWORD'], :database => secrets['DB_NAME'])

sql = <<-SQL
CREATE TABLE IF NOT EXISTS courses (
	ID INT NOT NULL,
	TEACHER_MID INT,
	TITLE VARCHAR(50) NOT NULL,
	PRIMARY KEY (ID)
);
SQL
@client.query(sql)

sql = <<-SQL
CREATE TABLE IF NOT EXISTS staffs (
	ID INT NOT NULL,
	USERNAME VARCHAR(30) NOT NULL,
	FIRST_NAME VARCHAR(15) NOT NULL,
	LAST_NAME VARCHAR(30) NOT NULL,
	DEPARTMENT VARCHAR(20),
	MPICTURE VARCHAR(100),
	PRIMARY KEY (ID)
);
SQL
@client.query(sql)

sql = <<-SQL
CREATE TABLE IF NOT EXISTS students (
	ID INT NOT NULL,
	USERNAME VARCHAR(30) NOT NULL,
	FIRST_NAME VARCHAR(15) NOT NULL,
	LAST_NAME VARCHAR(30) NOT NULL,
	ADVISEMENT VARCHAR(20),
	MPICTURE VARCHAR(100),
	PRIMARY KEY (ID)
);
SQL
@client.query(sql)

sql = <<-SQL
CREATE TABLE IF NOT EXISTS students_courses (
	ID INT NOT NULL AUTO_INCREMENT,
	student_id INT NOT NULL,
	course_id INT NOT NULL,
	PRIMARY KEY (ID)
);
SQL
@client.query(sql)

@grades = {
	"1" => 19,
	"2" => 18,
	"3" => 17,
	"4" => 16
}

def extract_person(mid, page)
	name = page.title.split(":")[0].split(" ")
	first_name = name[0]
	last_name = name[1]
	if name.length > 2
		last_name = name[1] + " " + name[2]
	end

	picture = page.search("a/img[@alt=\"Picture of #{first_name} #{last_name}\"]")[0]['src']
	type = :staff

	department = page.search("//dd[../dt = 'Department']/text()").to_s
	if /\A\d+\z/.match(department[0])
		type = :student
	end

	puts "#{mid.to_s}: #{type.capitalize} #{last_name}, #{first_name} of #{department}"

	if type == :staff
		username = (first_name[0] + last_name).downcase
		sql = "INSERT INTO staffs (ID, USERNAME, FIRST_NAME, LAST_NAME, DEPARTMENT, MPICTURE) VALUES(#{mid}, \"#{username}\", \"#{first_name}\", \"#{last_name}\", \"#{department}\", \"#{picture}\")"
		sql += " ON DUPLICATE KEY UPDATE USERNAME=\"#{username}\", FIRST_NAME=\"#{first_name}\", LAST_NAME=\"#{last_name}\", DEPARTMENT=\"#{department}\", MPICTURE=\"#{picture}\""
		puts sql
		@client.query(sql)
	else
		grade =  @grades[department[0]]
		username = (first_name[0] + last_name + grade.to_s).downcase
		sql = "INSERT INTO students (ID, USERNAME, FIRST_NAME, LAST_NAME, ADVISEMENT, MPICTURE) VALUES(#{mid}, \"#{username}\", \"#{first_name}\", \"#{last_name}\", \"#{department}\", \"#{picture}\")"
		sql += " ON DUPLICATE KEY UPDATE USERNAME=\"#{username}\", FIRST_NAME=\"#{first_name}\", LAST_NAME=\"#{last_name}\", ADVISEMENT=\"#{department}\", MPICTURE=\"#{picture}\""
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
		t_id2 = "TEACHER_MID=#{teacher_id}, "
	end

	sql = "INSERT INTO courses VALUES(#{mid}, #{t_id}, '#{title}') ON DUPLICATE KEY UPDATE #{t_id2}TITLE='#{title}'"
	@client.query(sql)
end


=begin
(1..700).each do |i|
	sleep(1)
	begin
		page = @agent.get("http://moodle.regis.org/course/view.php?id=" + i.to_s)
		if page.title == "Notice" or page.title == "Error"
			@client.query("DELETE FROM COURSES WHERE ID=#{i}")
			next
		end
		extract_course(i, page)
	rescue Mechanize::ResponseCodeError
		next
	end
end
=end

(1198..3000).each do |i|
	sleep(1)
	begin
		page = @agent.get("http://moodle.regis.org/user/profile.php?id=" + i.to_s)
		if page.title == "Notice" or page.title == "Error" or !page.title
			@client.query("DELETE FROM staffs WHERE ID=#{i}")
			@client.query("DELETE FROM students WHERE ID=#{i}")
		end
		extract_person(i, page)
	rescue Exception => e
		puts "Skipped #{i}"
		#puts e.inspect
		#puts e.backtrace.join("\n")
	end
end
