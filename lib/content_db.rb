require 'sqlite3'
require 'securerandom'

# db/content.db — копия db/main.db, в которой оставлены только таблицы из content_db_tables
# (config/config.yml). Используется rake db:content и GET /content.db.
module ContentDb
  SOURCE = File.expand_path('../db/main.db', __dir__)
  TARGET = File.expand_path('../db/content.db', __dir__)
  LOCK   = "#{TARGET}.lock"

  module_function

  # Актуальна ли копия: content.db новее main.db и её WAL (в WAL-режиме запись может не менять mtime main.db).
  def fresh?
    return false unless File.exist?(TARGET)
    src = [SOURCE, "#{SOURCE}-wal"].select { |f| File.exist?(f) }.map { |f| File.mtime(f) }.max
    File.mtime(TARGET) >= src
  end

  # Пересобирает content.db, если она устарела (или force). Параллельные вызовы ждут друг друга
  # на flock, сборка идёт во временный файл и ставится на место атомарным rename.
  def refresh!(tables, force: false)
    return TARGET if !force && fresh?

    File.open(LOCK, File::RDWR | File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)
      return TARGET if !force && fresh? # пока ждали, другой процесс уже обновил
      build(tables)
    end
    TARGET
  end

  def build(tables)
    keep = Array(tables).map(&:to_s)
    raise ArgumentError, 'content_db_tables пуст в config/config.yml' if keep.empty?

    tmp = "#{TARGET}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
    begin
      src = SQLite3::Database.new(SOURCE)
      src.busy_timeout = 30_000
      src.execute("VACUUM INTO '#{tmp}'")
      src.close

      db = SQLite3::Database.new(tmp)
      all = db.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").flatten
      (all - keep).each { |t| db.execute(%(DROP TABLE "#{t}")) }
      db.execute('VACUUM')
      db.close

      File.rename(tmp, TARGET)
      { kept: all & keep, dropped: all - keep, missing: keep - all }
    ensure
      File.delete(tmp) if File.exist?(tmp)
    end
  end
end
