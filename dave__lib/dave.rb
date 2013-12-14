require 'mysql2'

class Dave

  #system paths
  @@install_dir = "#{File.dirname(__FILE__)}/"
  @@script_path = "#{@@install_dir}scripts/"

  def initialize

    # Repo dir paths
    @current_dir 	= "#{Dir.pwd}/"
    @repo_dir 		= "#{@current_dir}.dave/"
    @update_dir		= "#{@repo_dir}update/"
    @rollback_dir	= "#{@repo_dir}rollback/"
    @config_dir		= "#{@repo_dir}config/"
    @temp_dir		= "#{@repo_dir}tmp/"

    # File paths
    @update_files 	= "#{@update_dir}*.sql"
    @rollback_files 	= "#{@rollback_dir}*.sql"
    @login_file		= "#{@config_dir}login"

    # databse login
    @database_credentials = {
      :host => nil,
      :username => nil,
      :password => nil,
      :database => nil
    }
    @client = nil


    # check if repo exists and isn't broken


  end


  def init


    if has_repo?
      puts "There is already a dave repo in your direcotry"
      puts "Would you like to override it?"
      puts "NOTE: all data of the repo will be lossed!"
      puts "[Y/n]"
      answer = STDIN.gets
      if answer =~ /[Yy]/
	#create table
	system "rm -rf #{@current_dir}.dave/"
	puts "remove old dave repo!"
      else
	abort("aborting!")
      end
    end
      system "cp -avr #{@@install_dir}init/.dave/ #{@current_dir}.dave/"
      puts "New dave repo was initialized!"
  end

  def create(args)

    check_repo_integrity
		puts args
    params = parse_create_args(args)

    script_path 		= params[:script]
    rollback_script_path 	= params[:rollback_script]
    release_type 		= params[:release_type]

    # prepend relative path if neccessary
    if script_path !~ /^\//
      script_path = "#{@current_dir}#{script_path}"
    end

    if rollback_script_path !~ /^\//
      rollback_script_path = "#{@current_dir}#{rollback_script_path}"
    end

    # check file existence
    unless FileTest.file? script_path
      abort "Couldn't find script #{script_path}"
    end

    unless FileTest.file? rollback_script_path
      abort "Couldn't find rollback script #{rollback_script_path}"
    end

    # get files
    script = File.open(script_path).read
    rollback_script = File.open(rollback_script_path).read

    # will abort if test fails
    #test_script(script, rollback_script)
		test_script_file(script_path, rollback_script_path)

    current_version = execute_script("fetch_latest_log").first


    #file_name = "#{current_version["major_release_number"]}"
		new_version_file = create_new_version_file_name(release_type)
		if new_version_file != "" && new_version_file != nil
			# write new scripts to files
			File.open("#{@update_dir}#{new_version_file}", 'w') {|f| f.write(script) }
			File.open("#{@rollback_dir}#{new_version_file}", 'w') {|f| f.write(rollback_script) }
		else
			abort "failed to create verion - failed to write to file"
		end

		abort "New change scripts added to repository"
  end

	def create_new_version_file_name(release_type)
		release_list = get_release_list
		latest_log = execute_script("fetch_latest_log")
		if latest_log.count > 0
			current_version_file = latest_log.first["file_name"]
			parsed_current_version = current_version_file.split('.')

			if release_type == :major
				parsed_latest_update =  release_list.pop.split('.')
				parsed_latest_update[1] = (parsed_latest_update[1].to_i) + 1
				parsed_latest_update[2] = 0
				parsed_latest_update[3] = 0

				#return
				parsed_latest_update.join('.')
			elsif release_type == :minor
				parsed_current_version[1] = (parsed_current_version[1].to_i) +1
				parsed_current_version[2] = 0
				parsed_current_version[3] = 0
				next_major = parsed_current_version.join('.')
				puts "next major: #{next_major}"

				previous_index = 0
				release_index = 0
				release_list.each do |update|

					if compare_version(next_major,update) == 0 || compare_version(next_major,update) == 1
						previous_index = release_index
					end
					release_index += 1
				end

				previous_release = release_list[previous_index]
				parsed_previous_update = previous_release.split('.')
				parsed_previous_update[2] = (parsed_previous_update[2].to_i) + 1
				parsed_previous_update[3] = 0

				#return
				parsed_previous_update.join('.')

			elsif release_type == :bugfix
				parsed_current_version[2] = (parsed_current_version[2].to_i) +1
				next_minor = parsed_current_version.join('.')

				previous_index = 0
				release_index = 0
				release_list.each do |update|

					if compare_version(next_minor,update) == 0 || compare_version(next_minor,update) == 1
						previous_index = release_index
					end
					release_index += 1
				end

				previous_release = release_list[previous_index]
				parsed_previous_update = previous_release.split('.')
				parsed_previous_update[3] = (parsed_previous_update[3].to_i) + 1

				#return
				parsed_previous_update.join('.')
			end
		else
			nil
		end
	end

	def get_current_version
		execute_script("fetch_latest_log").first["file_name"]
	end

	def list_updates
		check_repo_integrity
		puts "Installed updates"
		puts get_installed_updates
		puts "Current release"
		puts get_current_version
		puts "Available updates"
		puts get_available_updates
		abort
	end

  def update(args)

			check_repo_integrity

			available_updates = get_available_updates

			if args[0] == "-L"
				puts "Available updates:"
				abort available_updates
			else
				available_updates.each do |update|
					begin
						#execute_script("#{@update_dir}#{update}")
						callback = `mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} #{@database_credentials[:database]} < #{@update_dir}#{update}`
						puts "#{update} successful!"

					rescue Mysql2::Error
						abort "ERROR: #{update} failed!"
					end

					pared_update = update.split('.')
					major		= pared_update[1]
					minor		= pared_update[2]
					point		= pared_update[3]

					@client.query("
					              INSERT INTO
													`scheme_change_log`
												(
													major_release_number,
													minor_release_number,
													point_release_number,
													file_name
												)
												VALUES
												(
													#{major},
													#{minor},
													#{point},
													'#{update}'
												)")
				end
			end
			abort "update successfull!"
  end

	def version
		check_repo_integrity
		abort get_current_version
	end

	def rollback(args)

			check_repo_integrity

			available_updates = get_available_updates

			# list installed updates
			if args[0] == "-L"
				puts "Installed updates:"
				puts get_installed_updates

			# rollback one release
			elsif args.length == 0


					rollback = execute_script("fetch_latest_log").first["file_name"]

					puts "rolling back #{rollback}"

					begin
						execute_script("#{@rollback_dir}#{rollback}")
					rescue Mysql2::Error
						abort "Update #{update} failed - can't continue!"
					end

					@client.query("
					              DELETE FROM `scheme_change_log` WHERE file_name = '#{rollback}'
					             ")
					abort "rollback successful!"
			end
  end



  def push
      check_repo_integrity
      puts "Publishing scheme changes"
  end



  def setup(args)
      repo_exists? # will abort if not
      params = parse_setup_args(args)

      File.open(@login_file, 'w') do |file|
	file.write "#{params[:host]}\n#{params[:username]}\n#{params[:password]}\n#{params[:database]}"
      end
  end



  private
  def check_repo_integrity
    repo_exists?
    database_exists?
    changelog_exists?
    is_baselined?
    test_db_exists?
  end



  def parse_create_args(params)

    create_args = {}

    # parsing params
    i = 0;
    params.each do|arg|
      case arg
      when "-s"
	create_args[:script]= params[i+1]
	#puts "found script: #{script}"
      when "-rs"
	create_args[:rollback_script] = params[i+1]
	#puts "found rollback script: #{rollback_script}"
      when "-t"
				if params[i+1] =~ /major/
					release_type = :major
				end

				if params[i+1] =~ /(minor|feature)/
					release_type = :minor
				end

				if params[i+1] =~ /(point|bug|fix|bugfix)/
					release_type = :bugfix
				end

				create_args[:release_type] = release_type
      end
      i += 1
    end

		puts create_args

    return create_args
  end #END parse_create_args

  def parse_setup_args(params)

    setup_args = {
      :host => 'localhost',
      :username => 'root',
      :password => '',
      :database => ''
    }

    # parsing params
    i = 0;
    params.each do|arg|
      case arg
      when "-h"
	setup_args[:host]= params[i+1]
      when "-u"
	setup_args[:username] = params[i+1]
      when "-p"
	setup_args[:password] = params[i+1]
      when "-db"
	setup_args[:database] = params[i+1]
      end
      i += 1
    end

    return setup_args
  end #END parse_create_args


  def has_repo?
    FileTest.directory?(@repo_dir)
  end

  def repo_exists?
     # check if dave repo exists in current directory
    if FileTest.directory?(@repo_dir)
      unless FileTest.directory?(@update_dir)
	abort "Missing update directory. Your dave repo is broken!"
      end

      unless FileTest.directory?(@rollback_dir)
	abort "Missing rollback directory. Your dave repo is broken!"
      end

      unless FileTest.directory?(@config_dir)
	abort "Missing config directory. Your dave repo is broken!"
      end

    else
      abort "No dave repo found in #{@current_dir}\n" +
	    "* To create a new dave repo run 'dave init'"
    end
  end



  def set_database_credentials
    i = 1

    # check if login file exists
    if FileTest.file?(@login_file)


      # parse credentials
      File.open(@login_file, "r").each_line do |line|
		line = line.strip

		case i
		when 1
		@database_credentials[:host] = line
		when 2
		@database_credentials[:username] = line
		when 3
		@database_credentials[:password] = line
		when 4
		@database_credentials[:database] = line
		end

		i += 1
      end

      #puts "found db login file"

    else
      abort "No login file located - No database specifyed!\n" +
	"Try 'setup -h <hostname> -u <username> -p <password> -db <database>'"
    end
  end



  def database_exists?
    set_database_credentials
    begin
      #connect to database
      @client = Mysql2::Client.new(@database_credentials)

    rescue Mysql2::Error
      abort "couldn't connect to database through:" +
	    "#{@database_credentials}" +
	    "* run 'dave setup' to edit database connection"
    end
  end #END database_exists

  def is_baselined?
    unless execute_script("fetch_latest_log").count > 0
      puts "it seems as if your database isn't baselined yet"
      puts "would you like to use your current database scheme as a baseline?"
      puts "[Y/n]"
      answer = STDIN.gets
      if answer =~ /[Yy]/
	system "mysqldump -d -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} #{@database_credentials[:database]} > #{@update_dir}sc.1.0.0.sql"

	log_data = execute_script("insert_initial_log")

      else
	abort("aborting!")
      end
    end

    return true
  end


  def changelog_exists?

    unless execute_script("show_changelog_table").count == 1
      puts "You don't seem to have a changelog yet."
      puts "Would you like to create one?"
      puts "[Y/n]"
      answer = STDIN.gets
      if answer =~ /[Yy]/
	#create table
	execute_script("create_changelog")
      else
	abort("aborting!")
      end
    end

  end #END changelog_exists?

  def test_db_exists?
    if is_baselined?
      unless execute_script("show_testing_scheme").count == 1
	puts "You don't have a testing scheme yet."
	puts "Testing schemes are neccessary to guarantee working rollback scripts."
	puts "Do you want to set up a testing scheme now?"
	puts "[Y/n]"
	answer = STDIN.gets
	if answer =~ /[Yy]/
	  #create table
	  execute_script("create_test_database")
	  system "mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme < #{@update_dir}sc.1.0.0.sql"
	  puts "test db set up!"
	else
	  abort("aborting!")
	end
      end
    end
  end

  def test_script(script, rollback_script)
    test_db_exists?

    #clean up temp folder
    system "rm #{@temp_dir}dump_before_test.sql"
    system "rm #{@temp_dir}dump_after_test.sql"
    system "rm #{@temp_dir}differences.txt"

		# clone current scheme
		@client.query("DROP DATABASE `_dave_testing_scheme`")
		@client.query("CREATE DATABASE `_dave_testing_scheme`")
		system "mysqldump -d -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} #{@database_credentials[:database]} | mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme"


    #create dump from before the test
    system "mysqldump -d -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme > #{@temp_dir}dump_before_test.sql"

    begin
      @client.query("USE `_dave_testing_scheme`")
      @client.query(script)
    rescue Mysql2::Error
       # reset test scheme to before the test
      @client.query("DROP DATABASE `_dave_testing_scheme`")
      @client.query("CREATE DATABASE `_dave_testing_scheme`")
      system "mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme < #{@temp_dir}dump_before_test.sql"

      @client.query("USE `#{@database_credentials[:database]}`")
      puts script
      abort "test script failed!"
    end

    begin
      @client.query("USE `_dave_testing_scheme`")
      @client.query(rollback_script)


    rescue Mysql2::Error

      # reset test scheme to before the test
      @client.query("DROP DATABASE `_dave_testing_scheme`")
      @client.query("CREATE DATABASE `_dave_testing_scheme`")
      system "mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme < #{@temp_dir}dump_before_test.sql"

      @client.query("USE `#{@database_credentials[:database]}`")
      puts rollback_script
      abort "test rollback script failed!"
    end

    # dump after test
    system "mysqldump -d -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme > #{@temp_dir}dump_after_test.sql"

    # remove time reference from dump --> will always differ for big dumps
    remove_comments "#{@temp_dir}dump_before_test.sql"
    remove_comments "#{@temp_dir}dump_after_test.sql"

    @client.query("USE `#{@database_credentials[:database]}`")

    f1 = IO.readlines("#{@temp_dir}dump_before_test.sql").map(&:chomp)
    f2 = IO.readlines("#{@temp_dir}dump_after_test.sql").map(&:chomp)

    File.open("#{@temp_dir}differences.txt","w"){ |f| f.write((f1-f2).join("\n")) }

    differences = File.open("#{@temp_dir}differences.txt").read.strip

    unless differences == ""
      # reset test scheme to before the test
      @client.query("DROP DATABASE `_dave_testing_scheme`")
      @client.query("CREATE DATABASE `_dave_testing_scheme`")
      system "mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme < #{@temp_dir}dump_before_test.sql"

      puts "test failed!"
      puts differences
      abort "aborting!"
    end

		puts "successfull test!"

		#sorted_updates = get_release_list

  end

	def test_script_file(script, rollback_script)
    test_db_exists?

    #clean up temp folder
    system "rm #{@temp_dir}dump_before_test.sql"
    system "rm #{@temp_dir}dump_after_test.sql"
    system "rm #{@temp_dir}differences.txt"

		# clone current scheme
		@client.query("DROP DATABASE `_dave_testing_scheme`")
		@client.query("CREATE DATABASE `_dave_testing_scheme`")
		system "mysqldump -d -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} #{@database_credentials[:database]} | mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme"


    #create dump from before the test
    system "mysqldump -d -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme > #{@temp_dir}dump_before_test.sql"

    begin
      @client.query("USE `_dave_testing_scheme`")
      #@client.query(script)
			callback = `mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme < #{script}`
			puts "S callback: #{callback}"
    rescue Mysql2::Error
       # reset test scheme to before the test
      @client.query("DROP DATABASE `_dave_testing_scheme`")
      @client.query("CREATE DATABASE `_dave_testing_scheme`")
      system "mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme < #{@temp_dir}dump_before_test.sql"

      @client.query("USE `#{@database_credentials[:database]}`")
      puts script
      abort "test script failed!"
    end

    begin
      @client.query("USE `_dave_testing_scheme`")
      #@client.query(rollback_script)
			callback = `mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme < #{rollback_script}`
			puts "RS callback: #{callback}"

    rescue Mysql2::Error

      # reset test scheme to before the test
      @client.query("DROP DATABASE `_dave_testing_scheme`")
      @client.query("CREATE DATABASE `_dave_testing_scheme`")
      system "mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme < #{@temp_dir}dump_before_test.sql"

      @client.query("USE `#{@database_credentials[:database]}`")
      puts rollback_script
      abort "test rollback script failed!"
    end

    # dump after test
    system "mysqldump -d -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme > #{@temp_dir}dump_after_test.sql"

    # remove time reference from dump --> will always differ for big dumps
    remove_comments "#{@temp_dir}dump_before_test.sql"
    remove_comments "#{@temp_dir}dump_after_test.sql"

    @client.query("USE `#{@database_credentials[:database]}`")

    f1 = IO.readlines("#{@temp_dir}dump_before_test.sql").map(&:chomp)
    f2 = IO.readlines("#{@temp_dir}dump_after_test.sql").map(&:chomp)

    File.open("#{@temp_dir}differences.txt","w"){ |f| f.write((f1-f2).join("\n")) }

    differences = File.open("#{@temp_dir}differences.txt").read.strip

    unless differences == ""
      # reset test scheme to before the test
      @client.query("DROP DATABASE `_dave_testing_scheme`")
      @client.query("CREATE DATABASE `_dave_testing_scheme`")
      system "mysql -h #{@database_credentials[:host]} -u #{@database_credentials[:username]} -p#{@database_credentials[:password]} _dave_testing_scheme < #{@temp_dir}dump_before_test.sql"

      puts "test failed!"
      puts differences
      abort "aborting!"
    end

		puts "successfull test!"

		#sorted_updates = get_release_list

  end

	def get_release_list
		Dir["#{@update_dir}*.sql"].map{|y| remove_path y}.sort{|a,b| compare_version(a, b)}
	end

	def get_available_updates
		release_list = get_release_list

		latest_log = execute_script("fetch_latest_log")
		if latest_log.count > 0
			current_version_file = latest_log.first["file_name"]
			current_index = release_list.index(current_version_file)
			release_list[current_index + 1,release_list.length - current_index]
		else
			[]
		end
	end

	def get_installed_updates
		release_list = get_release_list
		latest_log = execute_script("fetch_latest_log")
		if latest_log.count > 0
			current_version_file = latest_log.first["file_name"]
			current_index = release_list.index(current_version_file)
			release_list[0, current_index + 1]
		else
			[]
		end
	end


	# extracts file from entire file path
	def remove_path(file_path)
		file_path.reverse.split("/", 2)[0].reverse
	end

	# compares version a with be
	# returns -1, 1 or 0 if equal
	def compare_version(a, b)

		#split into titl.maj.min.bug.ext
		a_segments = a.split('.')
		b_segments = b.split('.')

		#puts a_segments
		#puts b_segments

		#compare major 1.x.x
		case
		when a_segments[1].to_i < b_segments[1].to_i
			-1
		when a_segments[1].to_i > b_segments[1].to_i
			1
		else
			#compare minor 1.1.x
			case
			when a_segments[2].to_i < b_segments[2].to_i
			-1
			when a_segments[2].to_i > b_segments[2].to_i
				1
			else
				#compare point 1.1.1
				case
				when a_segments[3].to_i < b_segments[3].to_i
					-1
				when a_segments[3].to_i > b_segments[3].to_i
					1
				else
					0
				end
			end
		end #END comparator
	end

  # removes sql double dash comments --
  def remove_comments(filepath)
    text = File.read(filepath)
    replace = text.gsub(/^--.*$/, "")
    File.open(filepath, "w") {|file| file.puts replace}
  end

  def execute_script(file_name)

		if file_name !~ /^\//
			script_path = "#{@@script_path}#{file_name}"
		else
			script_path = file_name
		end


		if script_path !~ /\.sql$/
			script_path << ".sql"
		end

    if FileTest.file?(script_path)
      script = File.open(script_path).read
    else
      abort "#{script_path} - file doesn't exist!"
    end

    begin
      @client.query(script)
    rescue Mysql2::Error
      abort "#{script_path} - script failed!"
    end
  end

end