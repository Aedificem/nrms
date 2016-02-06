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
	id INT NOT NULL,
	teacher_id INT,
	title VARCHAR(50) NOT NULL,
	PRIMARY KEY (id)
);
SQL
@client.query(sql)

sql = <<-SQL
CREATE TABLE IF NOT EXISTS staffs (
	id INT NOT NULL,
	username VARCHAR(30) NOT NULL,
	first_name VARCHAR(15) NOT NULL,
	last_name VARCHAR(30) NOT NULL,
	department VARCHAR(20),
	mpicture VARCHAR(100),
	PRIMARY KEY (id)
);
SQL
@client.query(sql)

sql = <<-SQL
CREATE TABLE IF NOT EXISTS students (
	id INT NOT NULL,
	username VARCHAR(30) NOT NULL,
	first_name VARCHAR(15) NOT NULL,
	last_name VARCHAR(30) NOT NULL,
	advisement VARCHAR(20),
	mpicture VARCHAR(100),
	PRIMARY KEY (id)
);
SQL
@client.query(sql)

sql = <<-SQL
CREATE TABLE IF NOT EXISTS students_courses (
	id INT NOT NULL AUTO_INCREMENT,
	student_id INT NOT NULL,
	course_id INT NOT NULL,
	PRIMARY KEY (id)
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
		username = (first_name[0] + last_name).downcase.sub("'", "")
		sql = "INSERT INTO staffs (id, username, first_name, last_name, department, mpicture) VALUES(#{mid}, \"#{username}\", \"#{first_name}\", \"#{last_name}\", \"#{department}\", \"#{picture}\")"
		sql += " ON DUPLICATE KEY UPDATE username=\"#{username}\", first_name=\"#{first_name}\", last_name=\"#{last_name}\", department=\"#{department}\", mpicture=\"#{picture}\""
		@client.query(sql)
	else
		grade =  @grades[department[0]]
		username = (first_name[0] + last_name + grade.to_s).downcase.sub("'", "")
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

(1..700).each do |i|
	sleep(1)
	begin
		page = @agent.get("http://moodle.regis.org/course/view.php?id=" + i.to_s)
		if page.title == "Notice" or page.title == "Error"
			@client.query("DELETE FROM courses WHERE id=#{i}")
			next
		end
		extract_course(i, page)
	rescue Mechanize::ResponseCodeError
		next
	end
end

(3..3000).each do |i|
	sleep(1)
	begin
		page = @agent.get("http://moodle.regis.org/user/profile.php?id=" + i.to_s)
		if page.title == "Notice" or page.title == "Error" or !page.title
			@client.query("DELETE FROM staffs WHERE id=#{i}")
			@client.query("DELETE FROM students WHERE id=#{i}")
		end
		extract_person(i, page)
	rescue Exception => e
		puts "Skipped #{i}"
		#puts e.inspect
		#puts e.backtrace.join("\n")
	end
end
