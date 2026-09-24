namespace :links do
  desc "Проверяет статус ссылок (rake links:check_status [label=website] [days=15] [include_dead=true] [limit=500])"
  task :check_status do
    require 'parallel'

    days          = (ENV['days'] || 15).to_i
    label_name    = ENV['label']
    include_dead  = ENV['include_dead'] == 'true'
    limit         = ENV['limit']&.to_i

    scope = Link.where("checked_at IS NULL OR checked_at < ?", days.days.ago)
    scope = scope.where(active: true) unless include_dead
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

    stats = { active: 0, inactive: 0, redirected: 0, errors: 0 }
    mutex = Mutex.new

    record_stats = lambda do |link|
      mutex.synchronize do
        stats[link.active? ? :active : :inactive] += 1
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

    puts "Готово. active=#{stats[:active]} inactive=#{stats[:inactive]} redirected=#{stats[:redirected]} errors=#{stats[:errors]}"
  end
end
