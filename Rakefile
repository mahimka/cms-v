require './environment'
require 'sinatra/activerecord/rake'

require 'net/ssh'   
require 'net/scp'   
require 'net/sftp'  
require 'colorize'  

Dir.glob('tasks/*.rake').each { |r| import r }
Dir.glob('project/tasks/*.rake').each { |r| import r }
require_relative 'config/deploy.rb' if APP_ENV == "development" # чтобы не хранить пароль в файле на сервере??

# ==============================================

def upload files
  Net::SCP.start(@domain, @user, :password => @password) do |scp|
    files.each do |file|
      puts "copy #{file} to #{@app_name}/#{file}".white.on_green# + result.to_s
      result = scp.upload! file, "#{@app_name}/#{file}"
      puts ".. OK!".yellow if result == true
    end  
  end
end  

def run_ssh_commands commands
  Net::SSH.start(@domain, @user, password: @password) do |ssh|
    puts "Startin commands...."
    commands.each do |command|
      puts command.white.on_green
      result = ssh.exec!("source ~/.paths_for_rake && " + command )
  
      puts " .. " + result.to_s.yellow
      #puts " " 
    end
  end  
end

@commands = []