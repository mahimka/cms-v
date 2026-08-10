
namespace :remote do

  task :test do 

    puts "app_name: #{@app_name}"
    puts "repository: #{@repository}"

  end

  task :setup do
    @commands << "mkdir #{@app_name}"
    @commands << "git clone #{@repository} #{@app_name}"
    @commands << "cd #{@app_name} && bundle install"

    run_ssh_commands @commands
    @commands = []

    Rake::Task["upload:config"].invoke
    Rake::Task["upload:project"].invoke  

    # @commands << "cd #{@app_name} && rake db:schema:load RACK_ENV=production"
    # @commands << "cd #{@app_name} && rake db:create RACK_ENV=production "
    # @commands << "cd #{@app_name} && rake db:schema:load RACK_ENV=production DISABLE_DATABASE_ENVIRONMENT_CHECK=1"

    @commands << "passenger-config restart-app #{@deploy_to}" if @server == 'passenger'
    @commands << "cd #{@app_name} && bundle exec pumactl -P #{@deploy_to}/tmp/puma.pid restart" if @server == 'puma'

    run_ssh_commands @commands
  end  

  task :vacuum_main_db do 
    puts "Vacuum main.db ............. "
    @commands << "cd #{@app_name} && sqlite3 db/main.db 'VACUUM;'"
    run_ssh_commands @commands
  end  

  # нужно передавать команду параметром !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  task :command do 
    @commands = []
    # @commands << "cd #{@app_name} && rake fix_wrongly_assigned_parent_tags RACK_ENV=production"
    run_ssh_commands @commands
  end


  namespace :update do

    task :all do
       @commands << "cd #{@app_name} && git pull"
       @commands << "cd #{@app_name} && bundle install"

       run_ssh_commands @commands
       @commands = []

      Rake::Task["upload:config"].invoke
      Rake::Task["upload:project"].invoke
      
      @commands << "cd #{@app_name} && rake db:migrate RACK_ENV=production"
      
      @commands << "passenger-config restart-app #{@deploy_to}" if @server == 'passenger'
      @commands << "cd #{@app_name} && bundle exec pumactl -P #{@deploy_to}/tmp/puma.pid restart" if @server == 'puma'

      run_ssh_commands @commands
    end  

    task :code do
      @commands << "cd #{@app_name} && git pull"
      # @commands << "cd #{@app_name} && bundle install"

      run_ssh_commands @commands
      @commands = []

      @commands << "cd #{@app_name} && rake db:migrate RACK_ENV=production"

      @commands << "passenger-config restart-app #{@deploy_to}" if @server == 'passenger'
      @commands << "cd #{@app_name} && bundle exec pumactl -P #{@deploy_to}/tmp/puma.pid restart" if @server == 'puma'

      run_ssh_commands @commands
    end  

    task :config do
      Rake::Task["upload:config"].invoke
      
      @commands << "passenger-config restart-app #{@deploy_to}" if @server == 'passenger'
      @commands << "cd #{@app_name} && bundle exec pumactl -P #{@deploy_to}/tmp/puma.pid restart" if @server == 'puma'

      run_ssh_commands @commands
    end

    task :project do
      Rake::Task["upload:project"].invoke
      
      @commands << "passenger-config restart-app #{@deploy_to}" if @server == 'passenger'
      @commands << "cd #{@app_name} && bundle exec pumactl -P #{@deploy_to}/tmp/puma.pid restart" if @server == 'puma'

      run_ssh_commands @commands
    end

  end  


end










