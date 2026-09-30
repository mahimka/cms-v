# Первая запись потерянного запроса идёт не в SQLite, а в текстовый файл
# на диске — SQLite плохо держит частую конкурентную запись (несколько
# puma-воркеров/потоков разом), а lost-url трафик как раз такой (боты
# долбят одни и те же несуществующие пути пачками). Файл потом разбирает
# и upsert'ит в таблицу lost_urls кнопка в /admin/lost_urls (см.
# LostUrlsController) — там конкурентности уже нет, один admin-запрос.
module LostUrlLogger
  LOG_PATH = File.expand_path('../log/lost_urls.log', __dir__)

  # Табуляция как разделитель — единственный символ, которого точно не
  # будет ни в path (это URL), ни в датах; в referrer/ip на всякий случай
  # вычищаем табы/переводы строк, чтобы одна запись не порвалась на
  # несколько строк файла.
  def self.record(path:, referrer:, ip:)
    line = [Time.now.utc.iso8601, sanitize(path), sanitize(referrer), sanitize(ip)].join("\t")

    # File::APPEND — запись в конец атомарна на POSIX для строк меньше
    # PIPE_BUF, так что несколько процессов/потоков не порвут друг другу
    # строки даже без явного flock.
    File.open(LOG_PATH, File::WRONLY | File::CREAT | File::APPEND, 0o644) do |f|
      f.write("#{line}\n")
    end
  rescue StandardError => e
    # Логирование потерянного url не должно само по себе уронить ответ
    # пользователю — в худшем случае просто не записали.
    warn "LostUrlLogger#record failed: #{e.message}"
  end

  def self.sanitize(value)
    value.to_s.gsub(/[\t\r\n]/, ' ').strip.presence || '-'
  end
end
