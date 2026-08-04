# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever

# delayed_id = 
# every 10.minute do                                                    # delayed screenshots upload tmplate_id = 33
#   runner "UploadsController.upload_delayed(template_id, batch_size)"  # delayed screenshots upload tmplate_id = 33
# end               

                                                   # delayed screenshots upload tmplate_id = 33

# set :environment, "development"
set :output, {:error => "/home/deploy/list_items_error.txt"} # , :standard => "/home/deploy/image_upload_log.txt"
env :PATH, ENV['PATH']

every :day, at: ['8:30 am', '10:00 am'] do # 1.minute 1.day 1.week 1.month 1.year is also supported
   rake "release_random_items RACK_ENV=production"
end

every :day, at: ['10:00 am', '11:59 am'] do # 1.minute 1.day 1.week 1.month 1.year is also supported
   rake "release_random_items RACK_ENV=production"
end

every :day, at: ['1:00 pm', '3:00 pm'] do # 1.minute 1.day 1.week 1.month 1.year is also supported
   rake "release_random_items RACK_ENV=production"
end

every :day, at: ['3:00 pm', '6:00 pm'] do # 1.minute 1.day 1.week 1.month 1.year is also supported
   rake "release_random_items RACK_ENV=production"
end