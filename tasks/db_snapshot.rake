namespace :db do
  desc "Атомарный консистентный снимок db/main.db в db/main_snapshot.db — безопасно скачивать даже пока сервер работает (rake db:snapshot)"
  task :snapshot do
    require 'sqlite3'

    path = File.expand_path('db/main_snapshot.db', __dir__ + '/..')
    File.delete(path) if File.exist?(path)

    SQLite3::Database.new('db/main.db').execute("VACUUM INTO '#{path}'")

    puts "Snapshot written to #{path}"
  end
end
