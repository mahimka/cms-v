namespace :download do

  # что еще нужно скачивать?
  # gsc базу
  # config
  # все файлы pfoject

  task :images do 
    desc "rsync all REMOTE/images to LOCAL/images"
    system "rsync -avz --progress #{@user}@#{@domain}:/home/#{@user}/#{@app_name}/public/images/ public/images"
  end

  task :all do 
    desc "Downloads main.db and /config"
    Rake::Task["download:config"].invoke
    Rake::Task["download:db"].invoke
    # Rake::Task["download:display"].invoke
  end

  task :db do
    desc "Downloads main.db from remote/db and unzips to local/db"
    
    puts ''
    puts "Zipping on remote ...............".white.on_green
    @commands << "zip #{@app_name}/db/main_db.zip #{@app_name}/db/main.db"
    run_ssh_commands @commands

    puts "Downloading ...........".white.on_green

    Net::SFTP.start(@domain, @user, :password => @password) do |sftp|
      result = sftp.download!("/home/deploy/#{@app_name}/db/main_db.zip", "./db/main_db.zip", :progress => CustomHandler.new, :read_size => 64000)
      # puts "result:  " + result.to_s
    end

    puts ""
    puts "Unzipping ...............".white.on_green
    puts ""
    system "unzip -o -j db/main_db.zip -d db"

    puts ""
    puts "Removing on remote ..........".white.on_green
    @commands = []  
    @commands << "rm -f #{@app_name}/db/main_db.zip"
    run_ssh_commands @commands

    puts ""
    puts "Removing on local ...............".white.on_green
    puts ""
    system "rm -f db/main_db.zip"
  end

end

# для отобрпжения прогресса закачки
class CustomHandler
  def on_open(downloader, file)
    puts "  --> starting download: #{file.remote} -> #{file.local} (#{file.size} bytes)".white.on_green
  end

  def on_get(downloader, file, offset, data)
    puts "      writing #{data.length} bytes to #{file.local} starting at #{offset}"
  end

  def on_close(downloader, file)
    puts ""
    puts "  --> finished with #{file.remote}".white.on_green
    puts ""
  end

  def on_mkdir(downloader, path)
    puts "creating directory #{path}"
  end

  def on_finish(downloader)
    puts "  --> all done!".white.on_green
  end
end
