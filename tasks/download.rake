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
    desc "Downloads main.db from remote/db via rsync"

    puts ''
    puts "Snapshotting on remote (rake db:snapshot) ...............".white.on_green
    # zip живого main.db на бегу (сервер продолжает в него писать, а в
    # WAL-режиме свежие данные вообще лежат отдельно в main.db-wal) уже
    # ловил гонку и скачивал битый файл (database disk image is
    # malformed). db:snapshot делает атомарный VACUUM INTO — безопасно
    # при работающем сервере, см. tasks/db_snapshot.rake.
    # RACK_ENV=production обязателен: без него APP_ENV в Rakefile падает
    # на "development" и требует config/deploy.rb, которого на сервере
    # нет (не деплоится специально, чтобы не хранить пароль на сервере).
    @commands << "cd #{@app_name} && RACK_ENV=production bundle exec rake db:snapshot"
    run_ssh_commands @commands
    @commands = []

    puts "Downloading ...........".white.on_green
    system "rsync -avz --progress #{@user}@#{@domain}:#{@deploy_to}/db/main_snapshot.db db/main.db"

    puts ""
    puts "Removing on remote ..........".white.on_green
    @commands << "rm -f #{@app_name}/db/main_snapshot.db"
    run_ssh_commands @commands
    @commands = []
  end

end
