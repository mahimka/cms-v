namespace :links do
  desc "Проверяет статус ссылок (rake links:check_status [label=website] [days=15] [include_dead=true] [limit=500])"
  task :check_status do
    require 'parallel'

    days          = (ENV['days'] || 15).to_i
    label_name    = ENV['label']
    include_dead  = ENV['include_dead'] == 'true'
    limit         = ENV['limit']&.to_i

    scope = Link.where("checked_at IS NULL OR checked_at < ?", days.days.ago)
    scope = scope.where(alive: true) unless include_dead
    scope = scope.joins(:label).where(labels: { name: label_name }) if label_name

    # Сортируем от самых "старых" проверок — свежепроверенные не оттесняют
    # тех, кого не проверяли месяцами, если limit меньше общего количества.
    scope = scope.order(Arel.sql("checked_at IS NOT NULL, checked_at ASC"))
    scope = scope.limit(limit) if limit

    ids = scope.pluck(:id)
    puts "Найдено #{ids.size} ссылок для проверки#{label_name ? " (label: #{label_name})" : ""}"

    # По label — у кого выставлен check_delay_seconds (facebook/instagram
    # и т.п.), проверяем строго последовательно с паузой, чтобы не словить
    # блокировку; у кого нет (обычные сайты) — параллельно в потоках.
    links_by_label_delay = Link.where(id: ids).includes(:label).group_by { |l| l.label&.check_delay_seconds.to_i }

    stats = { alive: 0, dead: 0, redirected: 0, errors: 0 }
    mutex = Mutex.new

    record_stats = lambda do |link|
      mutex.synchronize do
        stats[link.alive? ? :alive : :dead] += 1
        stats[:redirected] += 1 if link.redirected?
        stats[:errors] += 1 if link.response.to_s.start_with?("error:")
      end
    end

    links_by_label_delay.each do |delay_seconds, links|
      if delay_seconds > 0
        label_names = links.map { |l| l.label&.name }.uniq.join(", ")
        puts "-- #{links.size} ссылок с задержкой #{delay_seconds}с между проверками (#{label_names}) --"

        links.each_with_index do |link, i|
          checked = link.check!
          puts "##{checked.id} [#{checked.label&.name}] #{checked.response} #{checked.url}"
          record_stats.call(checked)
          sleep delay_seconds unless i == links.size - 1
        end
      else
        puts "-- #{links.size} ссылок без задержки, параллельно --"

        Parallel.each(links.map(&:id), in_threads: 10) do |id|
          # Сетевой запрос (до ~20с с ретраем) — вне with_connection: иначе
          # поток держит соединение с БД занятым всё это время, и при
          # threads > pool (см. config/database.yml) остальные потоки
          # упираются в ActiveRecord::ConnectionTimeoutError и роняют весь
          # прогон. Соединение берём только на сами обращения к БД.
          link = ActiveRecord::Base.connection_pool.with_connection { Link.find_by(id: id) }
          next unless link

          result = LinkChecker.check(link.url)
          ActiveRecord::Base.connection_pool.with_connection { LinkChecker.apply_result!(link, result) }

          puts "##{link.id} [#{link.label&.name}] #{link.response} #{link.url}"
          record_stats.call(link)
        rescue StandardError => e
          # Одна ссылка не должна ронять прогон на 9000+ остальных —
          # логируем и продолжаем (Parallel.each иначе останавливает всё
          # на первом же необработанном исключении в любом потоке).
          puts "##{id}: не удалось проверить — #{e.class}: #{e.message}"
          mutex.synchronize { stats[:errors] += 1 }
        end
      end
    end

    puts "Готово. alive=#{stats[:alive]} dead=#{stats[:dead]} redirected=#{stats[:redirected]} errors=#{stats[:errors]}"
  end

  desc "Схлопывает 'косметические' редиректы (различие только в www. и/или конечном /) — url становится redirected_to, снимается redirected/response=200 (rake links:fold_trivial_redirects [label=website] [dry_run=true])"
  task :fold_trivial_redirects do
    require 'uri'

    label_name = ENV['label']
    dry_run = ENV['dry_run'] == 'true'

    # "Тривиальный" редирект — тот же scheme+host(без www.)+path(без конечного
    # /)+query, отличие только в www.-префиксе и/или конечном слэше. Смена
    # схемы (http->https), пути или домена сюда не попадает — это уже не
    # косметика, трогать не должны.
    normalize = lambda do |url|
      uri = URI.parse(url.to_s.strip)
      next nil unless uri.host

      host = uri.host.downcase.sub(/\Awww\./, '')
      path = uri.path.to_s.sub(%r{/\z}, '')
      "#{uri.scheme}://#{host}#{path}#{uri.query ? '?' + uri.query : ''}"
    rescue URI::InvalidURIError
      nil
    end

    scope = Link.where(redirected: true).where.not(redirected_to: [nil, ''])
    scope = scope.joins(:label).where(labels: { name: label_name }) if label_name

    folded = 0
    skipped = 0
    failed = 0

    scope.find_each do |link|
      a = normalize.call(link.url)
      b = normalize.call(link.redirected_to)

      unless a && b && a == b
        skipped += 1
        next
      end

      puts "##{link.id} #{link.url} -> #{link.redirected_to}#{dry_run ? ' (dry_run)' : ''}"
      next if dry_run

      # Другие rake-таски (websites:parse и т.п.) могут писать в ту же
      # sqlite параллельно — недолгий ретрай на контенцию, и в любом случае
      # одна проблемная запись (в т.ч. если её redirected_to кто-то параллельно
      # обнулил между чтением и записью) не должна ронять весь таск на
      # тысячах остальных.
      attempts = 0
      begin
        attempts += 1
        link.update!(url: link.redirected_to, redirected: false, redirected_to: nil, response: "200")
        folded += 1
      rescue ActiveRecord::StatementInvalid => e
        if e.message.include?("locked") && attempts < 5
          sleep(0.5 * attempts)
          retry
        end
        puts "  ##{link.id}: не удалось обновить — #{e.class}: #{e.message}"
        failed += 1
      rescue ActiveRecord::RecordInvalid => e
        puts "  ##{link.id}: не удалось обновить — #{e.class}: #{e.message}"
        failed += 1
      end
    end

    puts "Схлопнуто: #{folded}, пропущено (не тривиальный редирект — домен/путь реально другие): #{skipped}, не удалось: #{failed}"
  end
end
