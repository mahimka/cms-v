require 'net/ssh'   
require 'net/scp'   
require 'net/sftp'  
require 'colorize'  
#require 'dir'

# require_relative '../project/config/deploy.rb' if APP_ENV == "development" # чтобы не хранить пароль в файле на сервере??
require_relative '../../config/deploy.rb' if APP_ENV == "development" # чтобы не хранить пароль в файле на сервере??

@commands = []


task :setup_on_server do
  @commands << "mkdir #{@app_name}"
  @commands << "git clone #{@repository} #{@app_name}"
  @commands << "cd #{@app_name} && bundle install"

  run_ssh_commands @commands
  @commands = []

  Rake::Task["upload_config"].invoke
  Rake::Task["upload_project"].invoke  

  # @commands << "cd #{@app_name} && rake db:schema:load RACK_ENV=production"
  # @commands << "cd #{@app_name} && rake db:create RACK_ENV=production "
  # @commands << "cd #{@app_name} && rake db:schema:load RACK_ENV=production DISABLE_DATABASE_ENVIRONMENT_CHECK=1"

  @commands << "passenger-config restart-app #{@deploy_to}"

  run_ssh_commands @commands
end  

namespace :update do

  task :run_rake_command do 

    @commands = []
    @commands << "cd #{@app_name} && rake fix_wrongly_assigned_parent_tags RACK_ENV=production"

    run_ssh_commands @commands

  end

  task :all do
     @commands << "cd #{@app_name} && git pull"
     @commands << "cd #{@app_name} && bundle install"

     run_ssh_commands @commands
     @commands = []

    Rake::Task["upload_config"].invoke
    Rake::Task["upload_project"].invoke
    
    @commands << "cd #{@app_name} && rake db:migrate RACK_ENV=production"
    @commands << "passenger-config restart-app #{@deploy_to}"

    run_ssh_commands @commands
  end  

  task :cms_code do
    @commands << "cd #{@app_name} && git pull"
    @commands << "cd #{@app_name} && bundle install"

    run_ssh_commands @commands
    @commands = []

    @commands << "cd #{@app_name} && rake db:migrate RACK_ENV=production"
    @commands << "passenger-config restart-app #{@deploy_to}"

    run_ssh_commands @commands
  end  

  task :config_files do
    Rake::Task["upload_config"].invoke
    @commands << "passenger-config restart-app #{@deploy_to}"

    run_ssh_commands @commands
  end

  task :project_files do
    Rake::Task["upload_project"].invoke
    @commands << "passenger-config restart-app #{@deploy_to}"

    run_ssh_commands @commands
  end

end  

# для копирования файлов - обращаются к методу upload
task :upload_config do
  puts "Starts copying config files"
  desc "Upload files from project/config/ folder"
  upload @settings_files
end

# нужена синхронизация папок на локале и сервере??
task :upload_project do
  desc "Upload files from /project folders exept /config"
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
      dir_files = dir_files.reject {|x| x.include? "_" || x == ".gitignore" }
      
      dir_files.each do |file|
        result = sftp.upload("./#{file}", "/home/#{@user}/#{@app_name}/#{file}")
        puts "  " + file #if result == true
      end
    end


=begin

puts ""
    puts "=== Remote Dirs ==================="
   # puts !sftp.dir.glob("/home/deploy/#{@app_name}/display", "")#.map { |entry| entry.name }
    puts sftp.dir.entries("/home/deploy/#{@app_name}/display").map { |entry| entry.name }

puts ""
    puts "sftp.dir.foreach('/remote/path') do ..... " 

    sftp.dir.foreach("/home/deploy/#{@app_name}/display") do |entry|
      puts entry.name
    end

puts ""
    puts "sftp.dir.glob   **/*.erb ".white.on_green
    sftp.dir.glob("/home/deploy/#{@app_name}/display", "**/*.erb") do |entry|
      puts entry.name
    end

puts ""
    puts "sftp.dir.glob   **/* ".white.on_green
    sftp.dir.glob("/home/deploy/#{@app_name}/display", "**/*") do |entry|
      puts entry.name
    end    

=end

  end

end







