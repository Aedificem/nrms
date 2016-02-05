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
CREATE TABLE IF NOT EXISTS COURSES (
	ID INT NOT NULL,
	TEACHER_MID INT,
	TITLE VARCHAR(50) NOT NULL,
	PRIMARY KEY (ID)
);
SQL
@client.query(sql)

sql = <<-SQL
CREATE TABLE IF NOT EXISTS STAFF (
	ID INT NOT NULL,
	USERNAME VARCHAR(30) NOT NULL,
	FIRST_NAME VARCHAR(15) NOT NULL,
	LAST_NAME VARCHAR(30) NOT NULL,
	DEPARTMENT VARCHAR(20),
	MPICTIURE VARCHAR(100),
	PRIMARY KEY (ID)
);
SQL
@client.query(sql)

sql = <<-SQL
CREATE TABLE IF NOT EXISTS STUDENTS (
	ID INT NOT NULL,
	USERNAME VARCHAR(30) NOT NULL,
	FIRST_NAME VARCHAR(15) NOT NULL,
	LAST_NAME VARCHAR(30) NOT NULL,
	ADVISEMENT VARCHAR(20),
	MPICTURE VARCHAR(100)
	PRIMARY KEY (ID)
);
SQL
#@client.query(sql)

@grades = Hash.new
@grades[1] = 19
@grades[2] = 18
@grades[3] = 17
@grades[4] = 16

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
		statement = @client.prepare("INSERT INTO STAFF VALUES(?, ?, ?, ?, ?, ?)")
		statement.execute(mid, username, first_name, last_name, department, picture)
	else
		username = (first_name[0] + last_name + @grades[department[0]]).downcase
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
	
	sql = "INSERT INTO COURSES VALUES(#{mid}, #{t_id}, '#{title}') ON DUPLICATE KEY UPDATE #{t_id2}TITLE='#{title}'"
	puts sql
	@client.query(sql)
end


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


(1..3000).each do |i|
	sleep(1)
	begin
		page = @agent.get("http://moodle.regis.org/user/profile.php?id=" + i.to_s)
		if page.title == "Notice" or page.title == "Error" or !page.title
			@client.query("DELETE FROM STAFF WHERE ID=#{i}")
			#@client.query("DELETE * FROM STUDENTS WHERE MID=#{i}")
		end
		extract_person(i, page)
	rescue Exception => e
		puts e
	end
end
