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

namespace :db do
  desc "Копия db/main.db без лишних таблиц -> db/content.db; список таблиц — content_db_tables в config/config.yml (rake db:content)"
  task :content do
    keep = Array(App.settings.content_db_tables)
    abort "content_db_tables пуст в config/config.yml" if keep.empty?

    result = ContentDb.build(keep)
    warn "В main.db нет таблиц из content_db_tables: #{result[:missing].join(', ')}" if result[:missing].any?
    puts "Content DB written to #{ContentDb::TARGET} (#{(File.size(ContentDb::TARGET) / 1048576.0).round(1)} MB), " \
         "tables: #{result[:kept].size}, dropped: #{result[:dropped].join(', ')}"
  end
end
