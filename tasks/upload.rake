namespace :upload do

	task :schedule do
	  puts "Starts uploading schedule to remote"
	  desc "Upload config/schedule.rb to remote"
	  upload ['config/schedule.rb'] # Rakefile#upload
	end

	# для копирования файлов - обращаются к методу upload
	task :config do
	  puts "Starts copying config files"
	  desc "Upload files from config folder"
	  upload @settings_files
	end

	# нужена синхронизация папок на локале и сервере??
	task :project do
	  desc "Upload files from /project folders exept /config ?????????????????????????????????????????"
	  puts "Starts copying display files"

	  Net::SFTP.start(@domain, @user, :password => @password) do |sftp|
	    dirs = Dir.glob("**/", base: './project')
	    dirs = dirs.reject {|x| x.include? "config/" || x == "/" }
	    # dirs = dirs.reject {|x| x == "/" }
	    dirs.each do |dir|

	    puts dir.green

	    #  if !sftp.dir.glob("/home/deploy/#{@app_name}/display", "**/").map { |entry| entry.name }.include?(dir)
	    #    puts dir.to_s + " doesn't exist"
	        sftp.mkdir("/home/deploy/#{@app_name}/project/#{dir}")
	    #    puts "folder created!!".red.on_white
	    #  end

	      dir_files = Dir["./project/#{dir}*.*"]
	      dir_files = dir_files.reject {|x| x.starts_with? "_" || x == ".gitignore" }
	      
	      dir_files.each do |file|
	        result = sftp.upload("./#{file}", "/home/#{@user}/#{@app_name}/#{file}")
	        puts "  " + file #if result == true
	      end
	    end
	  end

    end

	# public/{images,fonts,javascripts,stylesheets} — гитигнорены (см. .gitignore,
	# внутри только .gitkeep), поэтому git pull их не привозит на сервер и
	# про них легко забыть при деплое (как с cookieconsent.js/css) — заливаем
	# отдельно, аналогично upload:project.
	task :public do
	  desc "Upload files from /public/{images,fonts,javascripts,stylesheets} (гитигнорены)"
	  puts "Starts copying public assets"

	  public_subdirs = %w[images fonts javascripts stylesheets]

	  Net::SFTP.start(@domain, @user, :password => @password) do |sftp|
	    public_subdirs.each do |subdir|
	      base = "./public/#{subdir}"
	      next unless Dir.exist?(base)

	      dirs = [''] + Dir.glob("**/", base: base)

	      dirs.each do |dir|
	        remote_dir = "/home/#{@user}/#{@app_name}/public/#{subdir}/#{dir}".sub(%r{/+\z}, '')

	        puts remote_dir.green

	        begin
	          sftp.mkdir!(remote_dir)
	        rescue Net::SFTP::StatusException
	          # папка уже существует на сервере — ок, не первый деплой
	        end

	        dir_files = Dir["#{base}/#{dir}*.*"].reject { |x| File.basename(x) == ".gitkeep" }

	        dir_files.each do |file|
	          remote_file = "/home/#{@user}/#{@app_name}/public/#{subdir}/#{dir}#{File.basename(file)}"
	          sftp.upload!(file, remote_file)
	          puts "  " + file
	        end
	      end
	    end
	  end
	end

end


