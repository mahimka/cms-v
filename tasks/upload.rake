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

  # Односторонняя синхронизация local -> remote через sqlite3_rsync (только изменённые страницы).
  # Реплика на сервере становится точной копией локальной базы, всё что менялось на ремоуте — теряется.
  # Защита: после синхронизации на ремоуте сохраняется mtime main.db (db/main.db.last_sync_mtime).
  # Если перед следующей синхронизацией mtime другой — база на сервере менялась после нас, задача останавливается.
  #
  #   rake upload:main_db_sync            # обычный запуск
  #   rake upload:main_db_sync FORCE=1    # перезаписать, даже если ремоут менялся (и первый запуск)
  #   LOCAL_DB=x.db REMOTE_DB=_test.db ... # другие файлы (для проверок)
  desc "Syncs db/main.db to remote with sqlite3_rsync (one-way, with remote-changed guard)"
  task :main_db_sync do
    require 'shellwords'

    local_db   = ENV['LOCAL_DB'] || 'db/main.db'
    abort "no such file: #{local_db}".red unless File.exist?(local_db)

    host       = "#{@user}@#{@domain}"
    remote_dir = "#{@deploy_to || "/home/#{@user}/#{@app_name}"}/db"
    remote_db  = "#{remote_dir}/#{ENV['REMOTE_DB'] || 'main.db'}"
    marker     = "#{remote_db}.last_sync_mtime"
    rsync_bin  = [File.expand_path('~/bin/sqlite3_rsync'), 'sqlite3_rsync'].find { |b| system("command -v #{b} >/dev/null 2>&1") }
    abort "sqlite3_rsync not found locally (~/bin or PATH)".red unless rsync_bin

    remote = lambda do |cmd|
      out = `ssh -o BatchMode=yes #{host} #{Shellwords.escape(cmd)} 2>&1`
      [$?.success?, out.strip]
    end

    # 1. защита: менялся ли ремоут после прошлой синхронизации
    ok, out = remote.call("stat -c %Y #{remote_db} 2>/dev/null || echo none; cat #{marker} 2>/dev/null || echo none")
    abort "ssh to #{host} failed (key set up?):\n#{out}".red unless ok
    remote_mtime, last_sync = out.lines.map(&:strip).last(2)

    if remote_mtime != 'none'
      problem =
        if last_sync == 'none'
          "no sync record on remote (first run, or the file was never synced from here)"
        elsif remote_mtime != last_sync
          "remote #{File.basename(remote_db)} changed after the last sync " \
          "(synced #{Time.at(last_sync.to_i)}, now #{Time.at(remote_mtime.to_i)})"
        end

      if problem
        if ENV['FORCE'] == '1'
          puts "FORCE=1: overwriting anyway -- #{problem}".white.on_red
        else
          abort "STOP: #{problem}\nRemote data would be lost. Check it, then rerun with FORCE=1.".white.on_red
        end
      end
    end

    # 2. синхронизация
    puts "sqlite3_rsync #{local_db} -> #{host}:#{remote_db}".white.on_green
    ok = system(rsync_bin, local_db, "#{host}:#{remote_db}", '--exe', "/home/#{@user}/bin/sqlite3_rsync", '-v')
    abort "sqlite3_rsync failed, remote marker not updated".red unless ok

    # 3. запоминаем mtime, который получила реплика
    ok, out = remote.call("stat -c %Y #{remote_db} > #{marker} && cat #{marker}")
    abort "synced, but could not write marker: #{out}".red unless ok
    puts ".. OK! synced, remote mtime #{Time.at(out.to_i)}".yellow
  end

end
