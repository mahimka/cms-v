require './environment'
require 'sinatra/activerecord/rake'

# import 'tasks/fill_ad_labels.rake' 
# import 'tasks/original_fill_ads.rake' 
# import 'tasks/original_import.rake' 
# import 'tasks/set_ancestry.rake' 
# import 'lib/tasks/deploy.rake' 
# import 'lib/tasks/service.rake' 
# import 'lib/tasks/parse_profiles.rake' 

Dir.glob('lib/tasks/*.rake').each { |r| import r }

# https://smartlogic.io/blog/2009-05-26-including-external-rake-files-in-your-projects-rakefile-keep-your-rake-tasks-organized/
Dir.glob('project/tasks/*.rake').each { |r| import r }


# import 'lib/tasks/transfer.rake' 
# import 'lib/tasks/yf_parse.rake'
# import 'lib/tasks/set_ads_for_profiles.rake'
# import 'lib/tasks/items.rake'
# import 'lib/tasks/geokit-test.rake'
# import 'lib/tasks/yf_parse_more.rake'
# import 'lib/tasks/yf_parse_links.rake'
# import 'lib/tasks/tags.rake'
# import 'lib/tasks/history-arrays.rake'


# task :release_random_items do 
#   # https://westonganger.com/posts/getting-random-records-in-rails
#   # Model.order("RANDOM()").first
  
#   Item.where(listed: false, ready: true).order("RANDOM()").first(10).each do |item|
    
#     item.listed = true
#     item.save
#     puts item.name
  
#     adm1 = item.adm1
#     adm1.lastmod = DateTime.now
#     puts adm1.name
#     adm1.save

#   end

# end


namespace :whenever do

    task :update do 
      Rake::Task["upload_schedule"].invoke
      @commands << "cd #{@app_name} && bundle exec whenever --update-crontab"
      run_ssh_commands @commands
    end

    task :clear  do 
      @commands << "cd #{@app_name} && bundle exec whenever --clear-crontab"
      run_ssh_commands @commands
    end

end  

task :release_items_remote do 
  @commands << "cd #{@app_name} && bundle exec rake release_random_items RACK_ENV=production"
  run_ssh_commands @commands
end


task :upload_schedule do
  puts "Starts uploading schedule to remote"
  desc "Upload config/schedule.rb to remote"
  upload ['config/schedule.rb'] # Rakefile#upload
end









# task :fix_wrongly_assigned_parent_tags do 

#   Tag.parenttags.each do |pt|
#     puts pt.name + " items: " + pt.items.size.to_s
#     Tagging.where(tag_id: pt.id).delete_all
#   end

# end

# task :populate_ads_with_lastmod do 
#     # Tag.all.each do |tag|
#     #   tag.lastmod = DateTime.now
#     #   # puts tag.lastmod
#     #   # puts "OK" if tag.save
#     #   tag.save!
#     # end

#     # Tag.all.each do |tag|
#     #   puts tag.lastmod
#     # end

#     Ad.all.each do |ad|
#       ad.lastmod = DateTime.now
#       ad.save
#     end
# end

# task :populate_tags_with_lastmod do 
#     # Tag.all.each do |tag|
#     #   tag.lastmod = DateTime.now
#     #   # puts tag.lastmod
#     #   puts "OK" if tag.save!
#     #   # tag.save
#     # end

#     # Tag.all.each do |tag|
#     #   puts tag.lastmod
#     # end

# end


# task :set_items_ready do 
#   Item.where(ready: false).each do |item|
#     item.ready = true
#     item.save
#   end 

# end


# task :set_profiles_ready do 
  
#   Profile.all.each do |profile|  
#     if !profile.pp.blank? && !profile.adm1.blank? && !profile.country.blank?
#       profile.ready = true 
#       profile.save
#       print "."
#     end  
#   end

# end



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
