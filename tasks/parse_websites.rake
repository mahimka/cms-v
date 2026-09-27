# Общий Parallel-прогон WebsiteScraper по списку id ссылок — используется и
# websites:parse (отбирает id сам по скоупу), и websites:retry_ids (id даёт
# вызывающий явным списком, см. там).
def run_website_scraper(ids, threads)
  stats = Hash.new(0)
  mutex = Mutex.new

  Parallel.each(ids, in_threads: threads) do |id|
    # В отличие от links:check_status (LinkChecker.check/apply_result! —
    # чистая сеть, потом чистая запись в БД, их можно развести по разные
    # стороны with_connection), WebsiteScraper#call сам пишет в Link/
    # Picture/Entity по ходу разбора страницы — соединение с БД держим
    # на всё время вызова, как и profiles:scrape_parallel для того же
    # рода Ferrum-скрапера (см. tasks/parse_profiles.rake).
    # 4 потока + отдельный puma-процесс админки пишут в один sqlite-файл —
    # PRAGMA busy_timeout=5000 сглаживает большую часть, но не всю
    # контенцию (наблюдали ~28% "database is locked" без ретрая на живом
    # прогоне). Ссылка тут ни при чём — просто не повезло с таймингом,
    # поэтому недолгий ретрай, а не сразу в error.
    result = nil
    attempts = 0
    begin
      attempts += 1
      result = ActiveRecord::Base.connection_pool.with_connection do
        link = Link.includes(:label).find_by(id: id)
        link ? WebsiteScraper.new(link).call : nil
      end
    rescue ActiveRecord::StatementInvalid => e
      if e.message.include?("locked") && attempts < 4
        sleep(0.5 * attempts)
        retry
      end
      raise
    end
    next unless result

    mutex.synchronize { stats[result[:status]] += 1 }
    puts "##{id} [#{result[:status]}] -- #{result[:message]}"
  rescue StandardError => e
    # Один сайт не должен ронять весь прогон по остальным — логируем
    # и продолжаем (Parallel.each иначе останавливает всё на первом же
    # необработанном исключении в любом потоке).
    puts "##{id}: не удалось обработать — #{e.class}: #{e.message}"
    mutex.synchronize { stats[:error] += 1 }
  end

  stats
end

namespace :websites do
  desc "Скриншот + контакты/соцссылки для website-ссылок entity через Ferrum (rake websites:parse [limit=] [days=30] [threads=4] [entity_id=123] [force=true] [retry_failed=true])"
  task :parse do
    require 'parallel'

    days    = (ENV['days'] || 30).to_i
    limit   = ENV['limit']&.to_i
    threads = (ENV['threads'] || 4).to_i
    force   = ENV['force'] == 'true'
    # true — вместо живых берём ровно то, что предыдущий прогон пометил
    # мёртвым (dead/error; for_sale сюда не попадает — LinkChecker
    # намеренно оставляет такие ссылки alive: true, это не техническая
    # неудача, а решение "пропустить", повторный заход ничего не изменит).
    retry_failed = ENV['retry_failed'] == 'true'

    # alive: true само по себе не значит "проверен и жив" — у только что
    # созданной, ещё ни разу не проверенной ссылки alive тоже true (см.
    # default в db/schema.rb) — поэтому дополнительно требуем checked_at
    # и его свежесть (не protухший статус).
    scope = Link.joins(:label).where(labels: { name: 'website' }, linkable_type: 'Entity', alive: !retry_failed)
    scope = scope.where.not(checked_at: nil).where("checked_at > ?", days.days.ago)
    scope = scope.where(linkable_id: ENV['entity_id']) if ENV['entity_id']

    # Идемпотентность: прогон на тысячи ссылок идёт часами — не пересобираем
    # скриншот у entity, у которой он уже есть, чтобы прогон можно было
    # спокойно прервать и продолжить. force=true — пересобрать всё заново.
    # active: true — иначе отклонённый вручную скриншот (active: false)
    # навсегда считался бы "уже готов" и никогда не переснимался заново.
    unless force
      already_done = Picture.where(imageable_type: 'Entity', active: true).where("file LIKE ?", "/images/screenshots/%").select(:imageable_id)
      scope = scope.where.not(linkable_id: already_done)
    end

    scope = scope.order(:id)
    scope = scope.limit(limit) if limit

    ids = scope.pluck(:id)
    puts "Найдено #{ids.size} #{retry_failed ? 'мёртвых (dead/error)' : 'живых'} website-ссылок для обработки"

    stats = run_website_scraper(ids, threads)
    puts "Готово. #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end

  desc "Повторный заход ровно по id ссылок из файла, по одному на строку (rake websites:retry_ids ids_file=/tmp/ids.txt [threads=3]) — для точечного ретрая после websites:parse, когда нужны конкретные id, а не весь alive:false скоуп"
  task :retry_ids do
    require 'parallel'

    ids_file = ENV['ids_file'] or raise "ids_file=... обязателен"
    threads = (ENV['threads'] || 3).to_i

    ids = File.readlines(ids_file).map(&:strip).reject(&:empty?).map(&:to_i)
    puts "Повторная попытка для #{ids.size} ссылок из #{ids_file}"

    stats = run_website_scraper(ids, threads)
    puts "Готово. #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end
end
