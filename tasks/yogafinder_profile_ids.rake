# Реестр ID профилей с yogafinder.com (csv/yogafinder.cm-business_ids.txt,
# 13686 штук) — шире, чем то, что у нас уже есть через Site "YogaFinder"
# (site_id=1, 10343 profiles, унаследованные из старого импорта
# old_yogamela.com, url вида .../yoga.cfm?yoganumber=N). Эта задача не
# парсит сами страницы (см. YogafinderParser, lib/parsers/) и не создаёt
# Entity — только регистрирует НЕДОСТАЮЩИЕ id как Profile-заглушки
# (profileable оставлен пустым, ссылку на Entity проставит будущий импорт-
# шаг, когда дойдёт до парсинга конкретного id).
namespace :yogafinder do
  desc "Добавить Profile-заглушки для ID из csv/yogafinder.cm-business_ids.txt, которых ещё нет (rake yogafinder:register_profile_ids [dry_run=true])"
  task :register_profile_ids do
    dry_run = ENV['dry_run'] == 'true'
    csv_path = File.expand_path('../csv/yogafinder.cm-business_ids.txt', __dir__)
    raise "Не найден #{csv_path}" unless File.exist?(csv_path)

    site = Site.find_by!(domain: 'yogafinder.com')

    ids = File.readlines(csv_path).map(&:strip).reject(&:empty?).uniq
    puts "ID в файле: #{ids.size}"

    existing_urls = Profile.where(site_id: site.id).pluck(:url).to_set
    added = []
    skipped = 0

    ActiveRecord::Base.transaction do
      ids.each do |id|
        url = "https://www.yogafinder.com/yoga.cfm?yoganumber=#{id}"

        if existing_urls.include?(url)
          skipped += 1
          next
        end

        Profile.create!(site_id: site.id, url: url, active: true)
        added << id
      end

      puts "Добавлено: #{added.size}, уже было: #{skipped}"
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово, добавлено #{added.size} profile(ей)"
  end

  desc <<~DESC
    Распарсить ВСЕ profiles yogafinder.com (Site domain='yogafinder.com') через
    YogafinderParser в csv/yogafinder_parsed.jsonl — одна JSON-строка на profile,
    результат (name/address/phone/description/markers/website) или {"error"=>...}.
    Ничего не пишет в БД — только staging-файл, импорт в Entity/Tag/Link отдельным
    шагом позже.

    Идемпотентно: при повторном запуске profile_id, уже встреченные в файле
    (успешно или с ошибкой), пропускаются — можно прерывать и перезапускать.

    ENV:
      limit=N              — распарсить не больше N штук за этот запуск (по умолчанию — все)
      threads=8            — сколько profile'ей обрабатывать параллельно (io-bound, поэтому
                              потоки, не процессы; каждый со своим Faraday-соединением)
      resolve_website=false — не резолвить website (быстрее, но без него)
      retry_errors=true    — пере-пытаться те profile_id, что в прошлый раз попали в файл с "error"

    rake yogafinder:parse_profiles [limit=50] [threads=8] [resolve_website=false] [retry_errors=true]
  DESC
  task :parse_profiles do
    require 'json'
    require_relative '../lib/parsers/yogafinder_parser'

    site = Site.find_by!(domain: 'yogafinder.com')
    out_path = File.expand_path('../csv/yogafinder_parsed.jsonl', __dir__)

    limit = ENV['limit']&.to_i
    threads_count = (ENV['threads'] || '8').to_i
    resolve_website = ENV['resolve_website'] != 'false'
    retry_errors = ENV['retry_errors'] == 'true'

    done_ok = Set.new
    done_error = Set.new
    if File.exist?(out_path)
      File.foreach(out_path) do |line|
        row = JSON.parse(line) rescue nil
        next unless row && row['profile_id']

        (row['error'] ? done_error : done_ok) << row['profile_id']
      end
    end
    puts "Уже в файле: ок #{done_ok.size}, с ошибкой #{done_error.size}#{retry_errors ? ' (будут пере-пытаны)' : ''}"

    work_items = Profile.where(site_id: site.id).order(:id).pluck(:id, :url).filter_map do |id, url|
      next if done_ok.include?(id)
      next if done_error.include?(id) && !retry_errors

      yoganumber = url[/yoganumber=(\d+)/, 1]
      yoganumber && [id, yoganumber]
    end
    work_items = work_items.first(limit) if limit
    total = work_items.size
    puts "К обработке: #{total} (threads=#{threads_count}, resolve_website=#{resolve_website})"

    queue = Queue.new
    work_items.each { |item| queue << item }
    threads_count.times { queue << nil } # по одному стоп-сигналу на поток

    out_mutex = Mutex.new
    out = File.open(out_path, 'a')
    counts = { parsed: 0, errors: 0, not_found: 0 }
    counts_mutex = Mutex.new
    started_at = Time.now

    workers = threads_count.times.map do
      Thread.new do
        # Короткие таймауты специально — при resolve_website: true каждый
        # profile это ещё 1-3 запроса на ПРОИЗВОЛЬНЫЕ внешние сайты (сам
        # сайт студии), и медленный/мёртвый домен не должен стопорить
        # весь прогон на 15+ тысячах profile'ей. Отдельное Faraday-
        # соединение на поток — Faraday::Connection не гарантированно
        # thread-safe для одновременных запросов на одном инстансе.
        connection = Faraday.new do |f|
          f.options.timeout = 6
          f.options.open_timeout = 3
          f.headers['User-Agent'] = 'Mozilla/5.0 (compatible; YogamelaImportBot/1.0)'
        end
        parser = YogafinderParser.new(connection: connection)

        loop do
          item = queue.pop
          break if item.nil?

          profile_id, yoganumber = item
          row = { 'profile_id' => profile_id, 'yoganumber' => yoganumber }
          kind = :parsed

          begin
            response = connection.get("#{YogafinderParser::BASE_URL}/yoga.cfm", yoganumber: yoganumber)
            data = parser.parse_html(response.body)

            if data['not_found']
              kind = :not_found
            else
              tracking_path = data.delete('website_tracking_path')
              data['website'] = resolve_website && tracking_path ? parser.resolve_website(tracking_path) : nil
            end

            row.merge!(data)
          rescue => e
            row['error'] = "#{e.class}: #{e.message}"
            kind = :errors
          end

          out_mutex.synchronize do
            out.puts(row.to_json)
            out.flush
          end

          counts_mutex.synchronize do
            counts[kind] += 1
            processed = counts.values.sum
            elapsed = Time.now - started_at
            rate = processed / elapsed
            eta_min = rate > 0 ? ((total - processed) / rate / 60).round : '?'
            print "\r#{processed}/#{total} (ок #{counts[:parsed]}, not_found #{counts[:not_found]}, ошибок #{counts[:errors]}) — #{rate.round(2)}/сек, ETA ~#{eta_min} мин   "
            $stdout.flush
          end
        end
      end
    end

    workers.each(&:join)
    out.close

    puts "\nГотово за #{((Time.now - started_at) / 60).round(1)} мин. " \
         "Распарсено: #{counts[:parsed]}, not_found: #{counts[:not_found]}, ошибок: #{counts[:errors]}"
  end

  desc <<~DESC
    Точечно переисправляет address в csv/yogafinder_parsed.jsonl (баг:
    #extract_address у листингов БЕЗ кнопок Website/Online Yoga забирал
    текст имени вместо адреса — задевало ~74% успешно распарсенных
    строк, см. обсуждение). Перекачивает СНОВА только те profile_id, где
    address == name (сигнатура бага), без resolve_website (сейчас всё
    равно не нужен — см. option 1). Переписывает файл целиком, заменяя
    затронутые строки исправленными (остальные — как есть, без похода в
    сеть).

    rake yogafinder:fix_addresses [threads=8]
  DESC
  task :fix_addresses do
    require 'json'
    require_relative '../lib/parsers/yogafinder_parser'

    out_path = File.expand_path('../csv/yogafinder_parsed.jsonl', __dir__)
    threads_count = (ENV['threads'] || '8').to_i

    rows = File.readlines(out_path).map { |l| JSON.parse(l) rescue nil }.compact
    broken = rows.select { |r| r['address'] && r['name'] && r['address'] == r['name'] }
    puts "Всего строк: #{rows.size}, с багом (address == name): #{broken.size}"

    queue = Queue.new
    broken.each { |r| queue << r }
    threads_count.times { queue << nil }

    counts_mutex = Mutex.new
    fixed = 0
    failed = 0
    started_at = Time.now

    workers = threads_count.times.map do
      Thread.new do
        connection = Faraday.new do |f|
          f.options.timeout = 6
          f.options.open_timeout = 3
          f.headers['User-Agent'] = 'Mozilla/5.0 (compatible; YogamelaImportBot/1.0)'
        end
        parser = YogafinderParser.new(connection: connection)

        loop do
          row = queue.pop
          break if row.nil?

          begin
            response = connection.get("#{YogafinderParser::BASE_URL}/yoga.cfm", yoganumber: row['yoganumber'])
            data = parser.parse_html(response.body)
            row['address'] = data['address']
            counts_mutex.synchronize { fixed += 1 }
          rescue => e
            counts_mutex.synchronize { failed += 1 }
          end

          counts_mutex.synchronize do
            processed = fixed + failed
            print "\r#{processed}/#{broken.size} (исправлено #{fixed}, ошибок #{failed})   "
            $stdout.flush
          end
        end
      end
    end
    workers.each(&:join)

    File.open(out_path, 'w') { |f| rows.each { |r| f.puts(r.to_json) } }

    puts "\nГотово за #{((Time.now - started_at) / 60).round(1)} мин. Исправлено: #{fixed}, не удалось: #{failed}"
  end

  desc <<~DESC
    Заливает csv/yogafinder_parsed.jsonl в Profile.details (JSON-колонка,
    тот же принцип, что у SnapShotParser — merge, не перезапись) — по
    profile_id из самой строки. Чистая работа с БД, без сети. markers
    (country/region/locality/styles) тоже кладутся в details как есть —
    отдельный будущий шаг превратит их в реальные Tag/Tagging у Entity
    (когда profileable появится).

    rake yogafinder:sync_to_profiles [dry_run=true]
  DESC
  task :sync_to_profiles do
    require 'json'

    dry_run = ENV['dry_run'] == 'true'
    jsonl_path = File.expand_path('../csv/yogafinder_parsed.jsonl', __dir__)
    raise "Не найден #{jsonl_path}, сначала rake yogafinder:parse_profiles" unless File.exist?(jsonl_path)

    updated = 0
    missing_profile = 0
    skipped_errors = 0

    ActiveRecord::Base.transaction do
      File.foreach(jsonl_path) do |line|
        row = JSON.parse(line) rescue nil
        next unless row && row['profile_id']

        profile = Profile.find_by(id: row['profile_id'])
        unless profile
          missing_profile += 1
          next
        end

        if row['error']
          skipped_errors += 1
          next
        end

        details = if row['not_found']
          { 'yogafinder_not_found' => true }
        else
          {
            'name' => row['name'],
            'address' => row['address'],
            'phone' => row['phone'],
            'description' => row['description'],
            'markers' => row['markers'],
            'website' => row['website']
          }.compact
        end

        profile.update!(details: (profile.details || {}).merge(details))
        updated += 1
      end

      puts "Обновлено profiles: #{updated}, без Profile в БД: #{missing_profile}, пропущено (error): #{skipped_errors}"
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  desc <<~DESC
    Создаёт Marker/ProfileMarker из profile.details['markers'] (группы
    country/region/locality/styles — см. yogafinder:sync_to_profiles) —
    тот же приём, что SnapShotParser#apply_markers для AI/детерминированных
    парсеров (Marker.where(group:, name:, site_id:).first_or_create +
    ProfileMarker), только источник markers — уже сохранённый details, без
    похода в сеть. Не трогает Tag/Tagging и Entity — это отдельный, более
    "сырой" уровень (Marker сам по себе can be привязан к Tag полем tag_id,
    но здесь мы это не делаем — ручная разметка/маппинг markers -> Tag
    оставлена человеку, как договорились).

    rake yogafinder:create_markers [dry_run=true]
  DESC
  task :create_markers do
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: 'yogafinder.com')

    profiles = Profile.where(site_id: site.id).where.not(details: nil)
    puts "Profiles с details: #{profiles.count}"

    markers_created = 0
    profile_markers_created = 0
    profiles_touched = 0
    without_markers = 0

    # Кэш существующих (group,name) -> Marker и (marker_id,profile_id) пар
    # ОДНИМ запросом каждый, вместо first_or_create на каждую пару (это
    # тоже сработало бы корректно, но: (а) N+1 запросов на ~50k пар
    # markers, (б) ActiveRecord 6.1 тут не умеет previously_new_record?
    # (появился в 7.1), чтобы посчитать just-created без лишнего запроса).
    existing_markers = Marker.where(site_id: site.id).each_with_object({}) do |m, h|
      h[[m.group, m.name]] = m.id
    end
    existing_profile_marker_pairs = ProfileMarker.joins(:marker).where(markers: { site_id: site.id })
      .pluck(:marker_id, :profile_id).to_set

    ActiveRecord::Base.transaction do
      profiles.find_each do |profile|
        markers = profile.details && profile.details['markers']
        if markers.blank?
          without_markers += 1
          next
        end

        touched = false

        markers.each do |group, values|
          Array(values).each do |value|
            name = value.to_s.strip[0, 240]
            next if name.empty?

            key = [group, name]
            marker_id = existing_markers[key]
            unless marker_id
              marker_id = Marker.create!(site_id: site.id, group: group, name: name).id
              existing_markers[key] = marker_id
              markers_created += 1
            end

            pair = [marker_id, profile.id]
            next if existing_profile_marker_pairs.include?(pair)

            ProfileMarker.create!(marker_id: marker_id, profile_id: profile.id)
            existing_profile_marker_pairs << pair
            profile_markers_created += 1
            touched = true
          end
        end

        profiles_touched += 1 if touched
      end

      puts "Markers создано: #{markers_created}, ProfileMarker создано: #{profile_markers_created}, " \
           "profiles затронуто: #{profiles_touched}, без markers в details: #{without_markers}"
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  desc <<~DESC
    Создаёт Marker(group: 'styles') из profile.details['markers']['styles'],
    сверяясь со словарём Tag (группы Yoga Style/Level/Special/Group/Modern
    Style/Age Group/Unsorted) — там, где нашлось уверенное совпадение
    (нормализация: без "yoga", lowercase, без пунктуации, порядок слов не
    важен), marker.tag_id проставляется сразу на найденный Tag, имя
    marker'а — каноничное имя тега. Без совпадения — marker всё равно
    создаётся (tag_id пустой, имя — Title Case от нормализованного
    текста, так разные варианты регистра/пробелов не плодят дубли) — под
    ручной разбор и перенос в tags "dirty" позже.

    Предполагает уже отработавший yogafinder:fix_styles (иначе "Email"/
    "Update listing"-мусор и неразбитые по "/" строки попадут в markers).

    rake yogafinder:create_style_markers [dry_run=true]
  DESC
  task :create_style_markers do
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: 'yogafinder.com')

    normalize = lambda do |s|
      s.to_s.downcase.gsub(/\byoga\b/, ' ').gsub(/[^a-z0-9]+/, ' ').strip.squeeze(' ')
    end

    dict_groups = ["Yoga Style", "Yoga Level", "Yoga Special", "Yoga Group", "Yoga Modern Style", "Yoga Age Group", "Unsorted"]
    dict = {}
    dict_wordset = {}
    dict_groups.each do |g|
      group_tag = Tag.find_by(name: g)
      next unless group_tag

      group_tag.children.each do |t|
        norm = normalize.call(t.name)
        dict[norm] ||= t
        dict_wordset[norm.split.sort.join(' ')] ||= t
      end
    end
    puts "Словарь: #{dict.size} тегов из #{dict_groups.size} групп"

    existing_markers = Marker.where(site_id: site.id).each_with_object({}) { |m, h| h[[m.group, m.name]] = m.id }
    existing_pairs = ProfileMarker.joins(:marker).where(markers: { site_id: site.id }).pluck(:marker_id, :profile_id).to_set

    markers_created = 0
    matched_to_tag = 0
    profile_markers_created = 0
    profiles_touched = 0
    without_styles = 0
    unmatched_occurrences = Hash.new(0) # marker name -> сколько profile'ей его получили

    ActiveRecord::Base.transaction do
      Profile.where(site_id: site.id).where.not(details: nil).find_each do |profile|
        styles = profile.details['markers'] && profile.details['markers']['styles']
        if styles.blank?
          without_styles += 1
          next
        end

        touched = false

        styles.each do |raw|
          norm = normalize.call(raw)
          next if norm.empty?

          tag = dict[norm] || dict_wordset[norm.split.sort.join(' ')]
          name = (tag ? tag.name : norm.split.map(&:capitalize).join(' '))[0, 240]

          key = ['styles', name]
          marker_id = existing_markers[key]
          unless marker_id
            marker = Marker.create!(site_id: site.id, group: 'styles', name: name, tag_id: tag&.id)
            marker_id = marker.id
            existing_markers[key] = marker_id
            markers_created += 1
            matched_to_tag += 1 if tag
          end

          unmatched_occurrences[name] += 1 unless tag

          pair = [marker_id, profile.id]
          next if existing_pairs.include?(pair)

          ProfileMarker.create!(marker_id: marker_id, profile_id: profile.id)
          existing_pairs << pair
          profile_markers_created += 1
          touched = true
        end

        profiles_touched += 1 if touched
      end

      puts "Markers создано: #{markers_created} (из них сразу с tag_id: #{matched_to_tag}), " \
           "ProfileMarker создано: #{profile_markers_created}, profiles затронуто: #{profiles_touched}, " \
           "без styles: #{without_styles}"
      raise ActiveRecord::Rollback if dry_run
    end

    puts "\nБез аналога в словаре тегов (топ 60 по числу profile'ей) — эти markers созданы, но tag_id пустой:"
    unmatched_occurrences.sort_by { |_, c| -c }.first(60).each { |name, c| puts "  #{c.to_s.rjust(5)}  #{name}" }
    puts "...ещё #{unmatched_occurrences.size - 60} названий" if unmatched_occurrences.size > 60

    puts dry_run ? "\nDRY RUN — откачено, ничего не сохранено" : "\nГотово"
  end

  desc <<~DESC
    Чинит styles в csv/yogafinder_parsed.jsonl после исправлений в
    YogafinderParser#extract_styles (index вместо "первый непустой" —
    убирает "Email"/"Update listing", просочившиеся вместо стилей) и
    STYLE_SPLIT_RE (добавлен "/" как разделитель):

    1. БЕЗ сети — досекает уже сохранённые styles по "/" (раньше "Kundalini
       Yoga/Meditation/Hatha/Flow/Vinyasa" оседало одной строкой).
    2. С сетью, но только для строк, где styles содержит "Email" или
       "Update listing" (сигнатура старого бага, ~1233 профиля) —
       перекачивает эти конкретные страницы и берёт styles заново.

    rake yogafinder:fix_styles [threads=8]
  DESC
  task :fix_styles do
    require 'json'
    require_relative '../lib/parsers/yogafinder_parser'

    out_path = File.expand_path('../csv/yogafinder_parsed.jsonl', __dir__)
    threads_count = (ENV['threads'] || '8').to_i

    rows = File.readlines(out_path).map { |l| JSON.parse(l) rescue nil }.compact

    resplit = 0
    rows.each do |row|
      styles = row.dig('markers', 'styles')
      next unless styles

      new_styles = styles.flat_map { |s| s.split(YogafinderParser::STYLE_SPLIT_RE) }.map(&:strip).reject(&:empty?).uniq
      if new_styles != styles
        row['markers']['styles'] = new_styles
        resplit += 1
      end
    end
    puts "Досечено по '/' (без сети): #{resplit}"

    junk = %w[Email Update\ listing]
    broken = rows.select { |r| Array(r.dig('markers', 'styles')).any? { |s| junk.include?(s) } }
    puts "С мусором (Email/Update listing), требуют перекачки: #{broken.size}"

    queue = Queue.new
    broken.each { |r| queue << r }
    threads_count.times { queue << nil }

    counts_mutex = Mutex.new
    fixed = 0
    failed = 0
    started_at = Time.now

    workers = threads_count.times.map do
      Thread.new do
        connection = Faraday.new do |f|
          f.options.timeout = 6
          f.options.open_timeout = 3
          f.headers['User-Agent'] = 'Mozilla/5.0 (compatible; YogamelaImportBot/1.0)'
        end
        parser = YogafinderParser.new(connection: connection)

        loop do
          row = queue.pop
          break if row.nil?

          begin
            response = connection.get("#{YogafinderParser::BASE_URL}/yoga.cfm", yoganumber: row['yoganumber'])
            data = parser.parse_html(response.body)
            row['markers']['styles'] = data.dig('markers', 'styles') || []
            row['markers'].delete('styles') if row['markers']['styles'].empty?
            counts_mutex.synchronize { fixed += 1 }
          rescue => e
            counts_mutex.synchronize { failed += 1 }
          end

          counts_mutex.synchronize do
            processed = fixed + failed
            print "\r#{processed}/#{broken.size} (исправлено #{fixed}, ошибок #{failed})   "
            $stdout.flush
          end
        end
      end
    end
    workers.each(&:join)

    File.open(out_path, 'w') { |f| rows.each { |r| f.puts(r.to_json) } }

    puts "\nГотово за #{((Time.now - started_at) / 60).round(1)} мин. Исправлено: #{fixed}, не удалось: #{failed}"
  end

  desc <<~DESC
    Заводит Tag под группой "Unsorted" на каждый Marker(group:'styles')
    без tag_id (после yogafinder:create_style_markers) и сразу проставляет
    marker.tag_id — дальше разбирать (переносить в правильную группу,
    сливать дубли-опечатки типа Astanga/Asthanga с Ashtanga Yoga и т.п.)
    предполагается руками через админку.

    Tag#name уникален ГЛОБАЛЬНО (across всех групп, не только внутри
    одной) — если тег с таким name уже где-то есть (в любой группе),
    новый не заводим, marker.tag_id просто указываем на существующий.

    rake yogafinder:tag_unmatched_style_markers [dry_run=true]
  DESC
  task :tag_unmatched_style_markers do
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: 'yogafinder.com')
    unsorted = Tag.find_by!(name: 'Unsorted', parent_id: [nil, 0])

    markers = Marker.where(site_id: site.id, group: 'styles', tag_id: nil)
    puts "Markers без tag_id: #{markers.count}"

    # Tag#name уникален глобально, но переиспользовать существующий тег
    # по совпадению name безопасно ТОЛЬКО если он сам из yoga-группы —
    # иначе рискуем привязать marker "Golden"/"Studio"/"Gym" к
    # ЛОКАЛИТИ-тегу "Golden" или Category-тегу "Studio" (реальный случай,
    # проверено на дай-ране: 11 таких коллизий, все — мусорные обрывки
    # текста в styles, а не настоящие стили). Для них — не переиспользуем
    # и не создаём: пропускаем, tag_id остаётся пустым, под ручной разбор.
    safe_groups = ["Unsorted", "Yoga Style", "Yoga Level", "Yoga Special", "Yoga Group", "Yoga Modern Style", "Yoga Age Group"].to_set

    existing = Tag.includes(:parent).each_with_object({}) { |t, h| h[t.name] = t }

    created_tags = 0
    reused_tags = 0
    skipped_collisions = []

    ActiveRecord::Base.transaction do
      markers.find_each do |marker|
        existing_tag = existing[marker.name]

        if existing_tag && !safe_groups.include?(existing_tag.parent&.name)
          skipped_collisions << "#{marker.name.inspect} (уже есть как Tag##{existing_tag.id} в группе #{existing_tag.parent&.name.inspect})"
          next
        end

        if existing_tag
          tag_id = existing_tag.id
          reused_tags += 1
        else
          tag = Tag.create!(name: marker.name, parent_id: unsorted.id, active: true)
          existing[marker.name] = tag
          tag_id = tag.id
          created_tags += 1
        end

        marker.update!(tag_id: tag_id)
      end

      puts "Тегов создано в Unsorted: #{created_tags}, переиспользовано существующих yoga-тегов (совпало name): #{reused_tags}"
      puts "Пропущено из-за коллизии с НЕ-yoga тегом: #{skipped_collisions.size}"
      skipped_collisions.each { |s| puts "  #{s}" }
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  desc <<~DESC
    Связывает Marker(group: country/region/locality) с Tag соответствующей
    гео-группы (addressCountry/addressRegion/addressLocality):

    1. Точное совпадение (без учёта регистра) — переиспользуем существующий
       Tag, marker.tag_id проставляется сразу.
    2. Небольшой словарь алиасов для country (yogafinder пишет "USA"/"Usa",
       у нас geonames-каноничное "United States"; "Netherlands" у нас "The
       Netherlands") — тоже переиспользуем.
    3. Нет соответствия — создаём НОВЫЙ Tag прямо в нужной группе, БЕЗ
       geonames_id (как и попросили) — это либо реально новая
       страна/регион/город, которых у нас ещё не было (большинство
       случаев — Wexford, Kerala, Bavaria... — 135 из 220 region-маркеров
       именно такие), либо специфичный для yogafinder нюанс (England/
       Scotland/Wales как отдельные "страны" в их breadcrumb).
    4. Если имя уже занято ДРУГИМ тегом НЕ из целевой группы (например
       нашёлся Tag "Milan" в addressLocality, а мы сейчас про region) —
       не переиспользуем (перепутали бы уровень иерархии) и не создаём
       (упёрлись бы в уникальность Tag#name) — пропускаем под ручной
       разбор, как и со styles.

    rake yogafinder:tag_geo_markers [dry_run=true]
  DESC
  task :tag_geo_markers do
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: 'yogafinder.com')

    group_map = {
      'country' => 'addressCountry',
      'region' => 'addressRegion',
      'locality' => 'addressLocality'
    }

    aliases = {
      'country' => {
        'usa' => 'United States',
        'netherlands' => 'The Netherlands'
      }
    }

    existing_by_name = Tag.includes(:parent).each_with_object({}) { |t, h| h[t.name] = t }

    created_tags = 0
    reused_tags = 0
    skipped_collisions = []

    ActiveRecord::Base.transaction do
      group_map.each do |marker_group, tag_group_name|
        tag_group = Tag.find_by!(name: tag_group_name, parent_id: [nil, 0])
        group_aliases = aliases[marker_group] || {}

        # Индекс по имени ВНУТРИ целевой группы (без учёта регистра) —
        # отдельно от глобального existing_by_name, чтобы не путать
        # "точно то же имя в этой же группе" с "то же имя в чужой группе".
        by_name_ci = tag_group.children.each_with_object({}) { |t, h| h[t.name.downcase] = t }

        markers = Marker.where(site_id: site.id, group: marker_group, tag_id: nil)
        puts "\n-- #{marker_group} -> #{tag_group_name}: markers без tag_id = #{markers.count} --"

        group_created = 0
        group_reused = 0

        markers.find_each do |marker|
          target_name = group_aliases[marker.name.downcase]
          same_group_tag = by_name_ci[(target_name || marker.name).downcase]

          if same_group_tag
            marker.update!(tag_id: same_group_tag.id)
            group_reused += 1
            next
          end

          collision = existing_by_name[marker.name]
          if collision
            skipped_collisions << "#{marker_group}: #{marker.name.inspect} (уже есть как Tag##{collision.id} в группе #{collision.parent&.name.inspect})"
            next
          end

          tag = Tag.create!(name: marker.name, parent_id: tag_group.id, active: true)
          by_name_ci[tag.name.downcase] = tag
          existing_by_name[tag.name] = tag
          marker.update!(tag_id: tag.id)
          group_created += 1
        end

        puts "  создано: #{group_created}, переиспользовано: #{group_reused}"
        created_tags += group_created
        reused_tags += group_reused
      end

      puts "\nИтого создано: #{created_tags}, переиспользовано: #{reused_tags}, пропущено (коллизия с чужой группой): #{skipped_collisions.size}"
      skipped_collisions.each { |s| puts "  #{s}" }
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "\nDRY RUN — откачено, ничего не сохранено" : "\nГотово"
  end

  desc <<~DESC
    Разруливает оставшиеся коллизии из yogafinder:tag_geo_markers (Marker
    country/region/locality без tag_id — их имя уже занято тегом из
    ДРУГОЙ группы, например "Wiltshire" уже есть в adm_2, а нужен
    отдельный тег для addressRegion) — заводит НОВЫЙ Tag в нужной группе
    с именем "<группа маркера> <имя>" (например "region Wiltshire"), т.к.
    Tag#name уникален глобально и просто "Wiltshire" второй раз завести
    нельзя. Тот же принцип, что уже применялся к geonames-коллизиям
    (Melilla / Melilla (ADM2) / Melilla (PPLA)), просто другой формат
    дисамбигуации — по запросу.

    rake yogafinder:tag_geo_marker_collisions [dry_run=true]
  DESC
  task :tag_geo_marker_collisions do
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: 'yogafinder.com')

    group_map = {
      'country' => 'addressCountry',
      'region' => 'addressRegion',
      'locality' => 'addressLocality'
    }

    created = 0
    skipped_still_colliding = []

    ActiveRecord::Base.transaction do
      group_map.each do |marker_group, tag_group_name|
        tag_group = Tag.find_by!(name: tag_group_name, parent_id: [nil, 0])
        markers = Marker.where(site_id: site.id, group: marker_group, tag_id: nil)
        puts "-- #{marker_group}: без tag_id = #{markers.count} --"

        group_created = 0

        markers.find_each do |marker|
          name = "#{marker_group} #{marker.name}"[0, 240]

          if Tag.exists?(name: name)
            skipped_still_colliding << "#{marker_group}: #{name.inspect} тоже уже занято"
            next
          end

          tag = Tag.create!(name: name, parent_id: tag_group.id, active: true)
          marker.update!(tag_id: tag.id)
          group_created += 1
        end

        puts "  создано: #{group_created}"
        created += group_created
      end

      puts "\nИтого создано: #{created}, всё ещё занято (редкий случай): #{skipped_still_colliding.size}"
      skipped_still_colliding.each { |s| puts "  #{s}" }
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "\nDRY RUN — откачено, ничего не сохранено" : "\nГотово"
  end

  desc <<~DESC
    Финальный шаг: Entity из Profile.details + Tagging из Marker.tag_id
    (см. tag_geo_markers/tag_unmatched_style_markers/tag_geo_marker_collisions
    — там markers уже связаны с Tag).

    - Profile без profileable (5393 новых из csv/yogafinder.cm-business_ids.txt)
      — заводит Entity (name/address, schema LocalBusiness, active: true),
      phone -> Detail (Label phone), website -> Link (Label website, только
      если есть — у большинства пусто, сайт резал ссылку под нагрузкой),
      profile.profileable проставляется на новую Entity.
    - Profile С profileable (10268 старых, из миграции old_yogamela.com) —
      Entity НЕ трогаем (name/address/phone/website не переписываем, это
      уже курируемые данные) — только теги.
    - Теги (country/region/locality/styles — все Marker.tag_id этого
      profile) — добавляются entity.taggings И новым, И старым Entity, без
      дублей (entity.taggings.exists?(tag_id:) — пропуск, если уже есть).
    - not_found profiles — пропускаются целиком (ни Entity, ни теги).

    rake yogafinder:create_entities_from_profiles [dry_run=true]
  DESC
  task :create_entities_from_profiles do
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: 'yogafinder.com')

    schema = Schema.find_by!(name: 'LocalBusiness')
    phone_label = Label.find_by!(name: 'phone')
    website_label = Label.find_by!(name: 'website')

    profiles = Profile.where(site_id: site.id).where.not(details: nil)
    puts "Profiles с details: #{profiles.count}"

    entities_created = 0
    not_found_skipped = 0
    taggings_added = 0
    phones_added = 0
    websites_added = 0
    entities_touched = 0

    ActiveRecord::Base.transaction do
      profiles.find_each do |profile|
        details = profile.details
        if details['yogafinder_not_found']
          not_found_skipped += 1
          next
        end

        entity = profile.profileable

        unless entity
          entity = Entity.create!(
            name: details['name'],
            address: details['address'],
            schema: schema,
            active: true
          )
          profile.update!(profileable: entity)
          entities_created += 1

          if details['phone'].present?
            Detail.create!(detailable: entity, label: phone_label, value: details['phone'])
            phones_added += 1
          end

          if details['website'].present?
            Link.create!(linkable: entity, label: website_label, url: details['website'], active: true)
            websites_added += 1
          end
        end

        tag_ids = profile.markers.where.not(tag_id: nil).distinct.pluck(:tag_id)
        touched = false
        tag_ids.each do |tag_id|
          next if entity.taggings.exists?(tag_id: tag_id)

          entity.taggings.create!(tag_id: tag_id)
          taggings_added += 1
          touched = true
        end
        entities_touched += 1 if touched
      end

      puts "Entity создано: #{entities_created}, Detail(phone) добавлено: #{phones_added}, " \
           "Link(website) добавлено: #{websites_added}"
      puts "Taggings добавлено: #{taggings_added} (entity затронуто тегами: #{entities_touched})"
      puts "not_found пропущено: #{not_found_skipped}"
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "\nDRY RUN — откачено, ничего не сохранено" : "\nГотово"
  end

  desc <<~DESC
    Пере-резолвит website для строк csv/yogafinder_parsed.jsonl, у которых он
    подозрительно пустой — profile нашёлся (not_found: false), явной ошибки
    не было, но website: null. Первый прогон parse_profiles резолвил website
    в 8 потоков БЕЗ троттлинга общего rate-limit у yogatracking.cfm (см.
    lib/yogatracking_throttle.rb) — лимит выбивало почти сразу, и такой
    website: null у подавляющего большинства строк на самом деле означает
    "не удалось проверить", а не "сайта нет" (на проверенном срезе — сайт
    нашёлся у 3 строк из 15754).

    Website резолвится заново НАПРЯМУЮ по yoganumber, без повторной загрузки
    самой страницы yoga.cfm (tracking_path детерминирован:
    yogatracking.cfm?yoganumber=N) — через тот же троттлер, что теперь стоит
    в YogafinderParser#resolve_website: строго последовательно, ~4с между
    запросами, с канарейкой на "пусто" (см. lib/yogatracking_throttle.rb).
    Уже проверенные строки (сайт найден ИЛИ подтверждённо отсутствует)
    помечаются website_checked: true и на следующих прогонах пропускаются —
    так что можно спокойно гонять этот таск повторно, пока не заберёт всё.

    Прогресс сохраняется в jsonl каждые 25 строк и в конце (в т.ч. при
    Ctrl+C) — атомарно, через tmp-файл + rename, так что исходный файл
    никогда не остаётся в половинчатом состоянии.

    ENV:
      limit=N — обработать не больше N строк за этот запуск (по умолчанию — все)

    rake yogafinder:reresolve_websites [limit=200]
  DESC
  task :reresolve_websites do
    require 'json'
    require_relative '../lib/parsers/yogafinder_parser'

    jsonl_path = File.expand_path('../csv/yogafinder_parsed.jsonl', __dir__)
    raise "Не найден #{jsonl_path}" unless File.exist?(jsonl_path)

    limit = ENV['limit']&.to_i

    rows = File.readlines(jsonl_path).filter_map { |line| JSON.parse(line) rescue nil }

    ambiguous_idx = rows.each_index.select do |i|
      row = rows[i]
      !row['not_found'] && !row['error'] && row['website'].nil? && !row['website_checked'] && row['yoganumber']
    end
    ambiguous_idx = ambiguous_idx.first(limit) if limit

    puts "Строк всего: #{rows.size}, под пере-резолв: #{ambiguous_idx.size}"

    connection = Faraday.new do |f|
      f.options.timeout = 10
      f.options.open_timeout = 5
      f.headers['User-Agent'] = 'Mozilla/5.0 (compatible; YogamelaImportBot/1.0)'
    end
    parser = YogafinderParser.new(connection: connection)

    save = -> {
      tmp_path = "#{jsonl_path}.tmp"
      File.open(tmp_path, 'w') { |f| rows.each { |r| f.puts(r.to_json) } }
      File.rename(tmp_path, jsonl_path)
    }

    resolved = 0
    confirmed_no_website = 0
    still_blocked = 0
    consecutive_blocked = 0
    started_at = Time.now
    # Если бан реально прилетел заново посреди многочасового прогона —
    # не молотить оставшиеся тысячи строк по MAX_ATTEMPTS*COOLDOWN (7.5
    # мин) каждую впустую: после нескольких подряд "забанено" останавливаемся,
    # сохранив уже сделанное — следующий запуск таска сам подхватит остаток.
    consecutive_blocked_limit = 3

    begin
      ambiguous_idx.each_with_index do |idx, i|
        row = rows[idx]
        begin
          website = parser.resolve_website(row['yoganumber'])
          row['website'] = website if website
          row['website_checked'] = true
          website ? (resolved += 1) : (confirmed_no_website += 1)
          consecutive_blocked = 0
        rescue YogaTrackingThrottle::BlockedError => e
          still_blocked += 1
          consecutive_blocked += 1
          puts "\n[blocked] yoganumber=#{row['yoganumber']}: #{e.message} — оставляю на следующий прогон"

          if consecutive_blocked >= consecutive_blocked_limit
            puts "\n#{consecutive_blocked_limit} бана подряд — похоже, забанены снова по-крупному. " \
                 "Останавливаюсь, не жгу время на заведомо безнадёжные попытки."
            break
          end
        end

        elapsed = Time.now - started_at
        rate = (i + 1) / elapsed
        eta_min = rate > 0 ? ((ambiguous_idx.size - i - 1) / rate / 60).round : '?'
        print "\r#{i + 1}/#{ambiguous_idx.size} (сайт найден #{resolved}, подтверждено нет #{confirmed_no_website}, забанено #{still_blocked}) — ETA ~#{eta_min} мин   "
        $stdout.flush

        save.call if (i + 1) % 25 == 0
      end
    ensure
      save.call
    end

    puts "\nГотово за #{((Time.now - started_at) / 60).round(1)} мин. " \
         "Сайт найден: #{resolved}, подтверждено что нет: #{confirmed_no_website}, всё ещё забанено (retry позже): #{still_blocked}"
  end

  desc <<~DESC
    Создаёт Link (label website) у Entity, для которых он ещё отсутствует —
    по данным, уже накопленным в Profile.details['website'] (Site
    domain='yogafinder.com'). В отличие от create_entities_from_profiles
    (который проставляет website ТОЛЬКО в момент первого создания Entity —
    у старых, унаследованных из old_yogamela.com Entity, Link никогда не
    заводился), этот таск смотрит от Entity: находит те, у кого нет ни
    одного Link(label: website), берёт их yogafinder Profile и, если там
    уже есть details['website'], заводит Link. Сам по сети ничего не
    резолвит — чисто БД-шаг, запускать после
    yogafinder:reresolve_websites + yogafinder:sync_to_profiles.

    rake yogafinder:sync_website_links [dry_run=true]
  DESC
  task :sync_website_links do
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: 'yogafinder.com')
    website_label = Label.find_by!(name: 'website')

    entities_with_link = Link.where(linkable_type: 'Entity', label_id: website_label.id)
                              .distinct.pluck(:linkable_id).to_set

    candidates = Profile.where(site_id: site.id, profileable_type: 'Entity')
                         .where.not(profileable_id: nil)
                         .where.not(details: nil)

    created = 0
    no_website = 0
    already_had_link = 0

    ActiveRecord::Base.transaction do
      candidates.find_each do |profile|
        if entities_with_link.include?(profile.profileable_id)
          already_had_link += 1
          next
        end

        website = profile.details['website']
        if website.blank?
          no_website += 1
          next
        end

        Link.create!(linkable_type: 'Entity', linkable_id: profile.profileable_id, label: website_label, url: website, active: true)
        entities_with_link << profile.profileable_id # на случай нескольких profiles у одной Entity
        created += 1
      end

      puts "Создано Link(website): #{created}, уже был линк: #{already_had_link}, в profile нет website: #{no_website}"
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end
end
