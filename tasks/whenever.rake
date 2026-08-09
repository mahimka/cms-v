namespace :remote do

    namespace :whenever do

        task :test do 
          @commands << "cd #{@app_name} && bundle exec whenever --clear-crontab"
          puts @commands.inspect
          puts @settings_files
        end

        task :update do 
          Rake::Task["upload:schedule"].invoke
          @commands << "cd #{@app_name} && bundle exec whenever --update-crontab"
          run_ssh_commands @commands
        end

        task :clear  do 
          @commands << "cd #{@app_name} && bundle exec whenever --clear-crontab"
          run_ssh_commands @commands
        end

    end  

    namespace :release do

      task :pages do 
      # @commands << "cd #{@app_name} && bundle exec rake release_random_pages RACK_ENV=production"
        run_ssh_commands @commands
      end

      task :pictures do 
        # @commands << "cd #{@app_name} && bundle exec rake release_random_pictures RACK_ENV=production"
        run_ssh_commands @commands
      end

    end

end



  # task :publish_random_page_and_picture do 

  #   page = Page.where(ready: true, published: false).first do |page|
 
  #     page.published = true

  #     if page.save
  #       picture = page.pictures.where(ready: true, published: false).first 
  #       picture.save if picture
  #     end

  #   end

  # end