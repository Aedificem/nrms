require 'mysql2'

module Database

  def initialize(config)
    @client = Mysql2::Client.new(:host => config["auth"]["mysql"]["host"], :username => config["auth"]["mysql"]["user"], :password => config["auth"]["mysql"]["password"], :database => config["auth"]["mysql"]["db"])

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

    @client.query("SELECT COUNT(*) as count FROM students").each do |row|
      puts "#{row['count']} students found!"
    end

    @client.query("SELECT COUNT(*) as count FROM courses").each do |row|
      puts "#{row['count']} courses found!"
    end

    @client.query("SELECT COUNT(*) as count FROM staffs").each do |row|
      puts "#{row['count']} staff found!"
    end
  end
end
