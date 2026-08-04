require './config/environment'
require 'sinatra/activerecord/rake'

# 1 parfumo.com


task :fetch_profiles do # rake fetch_profiles site_id=## profileable_type='Affprogram' / 'Operator'  rake fetch_profiles site_id=26 profileable_type='Operator'
    site = Site.find_by(id: ENV['site_id'])

    puts ENV['profileable_type']

    fetch_profiles = FetchProfiles.new(site, ENV['profileable_type'])

    fetch_profiles.get_profile_urls
    # fetch_profiles.save_to_baza
    # puts
    # puts fetch_profiles.report
    # puts "============================================"
end



# namespace :profiles do
#   desc "Scrape profiles based on site_id, profileable_type, and date threshold"
#   # task scrape: :environment do
#   task :scrape do
#     site_id = ENV['site_id']
#     profileable_type = ENV['profileable_type']
#     date_threshold = ENV['date']

#     # Проверяем обязательные параметры
#     unless site_id && profileable_type && date_threshold
#       puts "Error: Please provide site_id, profileable_type, and date."
#       puts "Usage: rake profiles:scrape site_id=1 profileable_type=Brand date='2026-01-01'"
#       exit
#     end

#     # Выбираем нужные профили по заданным условиям
#     profiles = Profile.where(site_id: site_id, profileable_type: profileable_type, active: true)
#                       .where(redirected: [false, nil])
#                       .where("scraped_at < ? OR scraped_at IS NULL", date_threshold)

#     puts "Found #{profiles.count} profiles to scrape."

#     profiles.find_each do |profile|
#       puts "Scraping profile ID: #{profile.id} (#{profile.url})..."
      
#       # Запускаем скрапер для каждого профиля
#       ProfileScraper.new(profile).call
      
#       # Небольшая пауза между запросами для вежливости к серверу
#       sleep(rand(1..2))
#     end

#     puts "Scraping finished!"
#   end
# end


# namespace :profiles do
#   desc "Scrape profiles based on site_id, profileable_type, and date threshold"
#   # task scrape: :environment do
#   task :scrape_back do
#     site_id = ENV['site_id']
#     profileable_type = ENV['profileable_type']
#     date_threshold = ENV['date']

#     # Проверяем обязательные параметры
#     unless site_id && profileable_type && date_threshold
#       puts "Error: Please provide site_id, profileable_type, and date."
#       puts "Usage: rake profiles:scrape site_id=1 profileable_type=Brand date='2026-01-01'"
#       exit
#     end

#     # Выбираем нужные профили по заданным условиям
#     profiles = Profile.where(site_id: site_id, profileable_type: profileable_type, active: true)
#                       .where(redirected: [false, nil])
#                       .where("scraped_at < ? OR scraped_at IS NULL", date_threshold).order(id: :desc)

#     puts "Found #{profiles.count} profiles to scrape."

#     profiles.each do |profile|
#       puts "Scraping profile ID: #{profile.id} (#{profile.url})..."
      
#       # Запускаем скрапер для каждого профиля
#       ProfileScraper.new(profile).call
      
#       # Небольшая пауза между запросами для вежливости к серверу
#       sleep(rand(1..2))
#     end

#     puts "Scraping finished!"
#   end
# end


namespace :profiles do
  desc "Scrape profiles concurrently"
  task :scrape_parallel do
    require 'parallel'

    site_id = ENV['site_id']
    profileable_type = ENV['profileable_type']
    date_threshold = ENV['date']

    unless site_id && profileable_type && date_threshold
      puts "Error: Please provide site_id, profileable_type, and date."
      exit
    end

    # Вытаскиваем только ID профилей, чтобы не держать объекты ActiveRecord в памяти потоков
    profile_ids = Profile.where(site_id: site_id, profileable_type: profileable_type, active: true)
                          .where(redirected: [false, nil])
                          .where("scraped_at < ? OR scraped_at IS NULL", date_threshold)
                          # .order(id: :desc)
                          .pluck(:id)

    total = profile_ids.count
    puts "Found #{total} profiles to scrape. Starting parallel scraping..."

    Parallel.each(profile_ids, in_threads: 10) do |id|
      ActiveRecord::Base.connection_pool.with_connection do
        # Находим профиль заново *внутри* потока и сразу закрываем/освобождаем соединение после отработки
        profile = Profile.find_by(id: id)
        if profile
          puts "Scraping profile ID: #{profile.id}..."
          ProfileScraper.new(profile).call
        end
      end
    end

    puts "Scraping finished!"
  end
end