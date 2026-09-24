require 'sqlite3'

# Лёгкие модели на ОТДЕЛЬНОМ подключении к чужой SQLite-базе того же
# приложения (например ../cms-diversorio/db/main.db) — не трогают
# основное ActiveRecord::Base.connection, поэтому текущий проект спокойно
# продолжает читать/писать свою БД, пока мы читаем чужую.
class ExternalDbConnection < ActiveRecord::Base
  self.abstract_class = true
end

class SourceTag < ExternalDbConnection
  self.table_name = 'tags'
end

class SourceMarker < ExternalDbConnection
  self.table_name = 'markers'
  belongs_to :tag, class_name: 'SourceTag', optional: true
end

def connect_external_db!(path)
  raise "Укажи путь к чужой БД: db_path=/path/to/other/project/db/main.db" if path.blank?
  raise "Файл не найден: #{path}" unless File.exist?(path)

  ExternalDbConnection.establish_connection(adapter: 'sqlite3', database: path)
end

namespace :tags do
  desc "Скопировать теги (иерархию Tag) из БД другого проекта на этом же коде, без дублей по имени (rake tags:import_from db_path=../cms-diversorio/db/main.db [dry_run=true])"
  task :import_from do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    # Не у всех источников совпадает набор колонок (например, старые
    # дореформенные схемы вроде old_*.com/tags не знают short_2/icon_svg
    # и хранят активность как listed+ready, а не active) — берём то, что
    # есть, без ошибки на отсутствующих колонках.
    source = SourceTag.all.map do |t|
      {
        'id' => t.id,
        'name' => t.name,
        'parent_id' => t.parent_id,
        'position' => t.respond_to?(:position) ? t.position : nil,
        'short' => t.respond_to?(:short) ? t.short : nil,
        'short_2' => t.respond_to?(:short_2) ? t.short_2 : nil,
        'active' => t.respond_to?(:active) ? t.active : (t.respond_to?(:listed) && t.respond_to?(:ready) ? (t.listed && t.ready) : nil),
        'icon_svg' => t.respond_to?(:icon_svg) ? t.icon_svg : nil
      }
    end
    roots, children = source.partition { |t| t['parent_id'].nil? }

    id_map = {}
    created = []
    reused = 0

    resolve = lambda do |t|
      existing = Tag.find_by(name: t['name'])
      if existing
        id_map[t['id']] = existing.id
        reused += 1
      else
        parent_id = t['parent_id'] ? id_map[t['parent_id']] : nil
        tag = Tag.create!(
          name: t['name'],
          parent_id: parent_id,
          position: t['position'],
          short: t['short'],
          short_2: t['short_2'],
          active: t['active'].nil? ? true : t['active'],
          icon_svg: t['icon_svg']
        )
        id_map[t['id']] = tag.id
        created << t['name']
      end
    end

    ActiveRecord::Base.transaction do
      roots.each { |t| resolve.call(t) }
      children.each { |t| resolve.call(t) }

      puts "Найдено в источнике: #{source.size}, уже было (переиспользовано по имени): #{reused}, создано новых: #{created.size}"
      puts created.join(', ') if created.any?

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Tag.count теперь #{Tag.count}"
  end

  desc "Проставить Marker.tag_id: сперва по карте соответствий group+name->tag.name уже размеченных маркеров другого проекта, потом по точному совпадению имени (rake tags:link_markers db_path=../cms-diversorio/db/main.db [site=tripadvisor.com] [dry_run=true])"
  task :link_markers do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: ENV['site'] || 'tripadvisor.com')

    ref_map = {}
    SourceMarker.where.not(tag_id: nil).includes(:tag).find_each do |m|
      next unless m.tag

      key = [m.group, m.name.to_s.strip.downcase]
      ref_map[key] ||= m.tag.name
    end
    puts "Карта соответствий из источника: #{ref_map.size} пар group+name -> tag.name"

    markers = Marker.where(site_id: site.id, tag_id: nil)
    puts "Маркеров без tag_id: #{markers.count}"

    via_reference = 0
    via_direct = 0
    unmatched = []

    ActiveRecord::Base.transaction do
      markers.find_each do |m|
        key = [m.group, m.name.to_s.strip.downcase]
        tag_name = ref_map[key]
        tag = tag_name && Tag.find_by(name: tag_name)

        if tag
          via_reference += 1
        else
          tag = Tag.find_by(name: m.name) || Tag.where('LOWER(name) = ?', m.name.to_s.strip.downcase).first
          via_direct += 1 if tag
        end

        if tag
          m.update!(tag_id: tag.id)
        else
          unmatched << "#{m.group} / #{m.name}"
        end
      end

      puts "via_reference=#{via_reference} via_direct=#{via_direct} unmatched=#{unmatched.size}"

      raise ActiveRecord::Rollback if dry_run
    end

    if unmatched.any?
      puts "--- unmatched (по группам) ---"
      unmatched.group_by { |u| u.split(' / ').first }.each { |g, list| puts "#{g}: #{list.size}" }
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  desc "Для маркеров сайта, у которых так и не нашёлся tag_id, создать группу ta_<группа маркера> и тег с именем маркера; при занятом имени добавляет _ta (rake tags:create_missing db_path=... [site=tripadvisor.com] [dry_run=true])"
  task :create_missing do
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: ENV['site'] || 'tripadvisor.com')

    markers = Marker.where(site_id: site.id, tag_id: nil).order(:group, :name)
    puts "Маркеров без tag_id: #{markers.count}"

    unique_tag_name = lambda do |base_name|
      name = base_name
      name = "#{base_name}_ta" while Tag.exists?(name: name)
      name
    end

    created_groups = []
    created_tags = 0
    linked = 0

    ActiveRecord::Base.transaction do
      markers.group_by(&:group).each do |group_name, group_markers|
        group_tag_name = "ta_#{group_name}"
        group_tag = Tag.find_by(name: group_tag_name)
        if group_tag.nil?
          group_tag = Tag.create!(name: group_tag_name, parent_id: nil, active: true)
          created_groups << group_tag_name
        end

        group_markers.each do |m|
          tag = Tag.find_by(name: m.name)
          if tag.nil?
            final_name = unique_tag_name.call(m.name)
            tag = Tag.create!(name: final_name, parent_id: group_tag.id, active: true)
            created_tags += 1
          end
          m.update!(tag_id: tag.id)
          linked += 1
        end
      end

      puts "Новых групп: #{created_groups.size} (#{created_groups.join(', ')})"
      puts "Новых тегов: #{created_tags}, привязано маркеров: #{linked}"

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Tag.count теперь #{Tag.count}"
  end

  desc <<~DESC
    Сливает несколько тегов-дублей/опечаток в один целевой: у исходных
    тегов перевешивает Tagging (если у того же объекта уже есть Tagging
    на целевой тег — дубликат просто дропается, а не переносится) и
    Marker.tag_id на целевой, затем удаляет исходные теги (только листья
    — PreventDestroyWithChildren не даст удалить тег с детьми).

    Исходные теги — явным списком id, либо префиксом/подстрокой имени
    внутри группы:
      rake tags:merge ids=4401,4504,4588 into=7757 [dry_run=true]
      rake tags:merge prefix="200" group="Unsorted" into=7757 [dry_run=true]
      rake tags:merge contains="senior" group="Unsorted" into=25 [dry_run=true]
  DESC
  task :merge do
    dry_run = ENV['dry_run'] == 'true'
    into_id = ENV['into']&.to_i
    raise "укажи into=<id целевого тега>" unless into_id

    target = Tag.find(into_id)

    source_ids =
      if ENV['ids']
        ENV['ids'].split(',').map(&:to_i)
      elsif ENV['prefix'] && ENV['group']
        group_tag = Tag.find_by!(name: ENV['group'])
        group_tag.children.where("name LIKE ?", "#{ENV['prefix']}%").pluck(:id)
      elsif ENV['contains'] && ENV['group']
        group_tag = Tag.find_by!(name: ENV['group'])
        group_tag.children.where("name LIKE ?", "%#{ENV['contains']}%").pluck(:id)
      else
        raise "укажи либо ids=1,2,3, либо prefix=.../contains=... group=..."
      end
    source_ids = source_ids.uniq - [target.id]

    puts "Тег-цель: ##{target.id} #{target.name.inspect} (группа #{target.parent&.name.inspect})"
    puts "Исходных тегов: #{source_ids.size} — #{Tag.where(id: source_ids).pluck(:name).join(', ')}"

    taggings_moved = 0
    taggings_dropped_dupe = 0
    markers_relinked = 0
    tags_destroyed = 0

    ActiveRecord::Base.transaction do
      source_ids.each do |sid|
        source = Tag.find(sid)

        source.taggings.each do |tg|
          if Tagging.exists?(tag_id: target.id, taggable_type: tg.taggable_type, taggable_id: tg.taggable_id)
            tg.destroy!
            taggings_dropped_dupe += 1
          else
            tg.update!(tag_id: target.id)
            taggings_moved += 1
          end
        end

        Marker.where(tag_id: source.id).find_each do |m|
          m.update!(tag_id: target.id)
          markers_relinked += 1
        end

        # Tag has_many :taggings, dependent: :destroy — если не сбросить
        # закешированную в памяти ассоциацию (мы её только что итерировали
        # выше через source.taggings.each), destroy! удалит из БД ровно те
        # объекты Tagging, что в кеше — включая уже перевешенные на target
        # (у них tag_id в памяти всё ещё source.id, хотя в БД уже
        # target.id) — реальный баг, поймали на "200"-слиянии: 17 из 18
        # taggings исчезли молча, хотя move отчитался об успехе.
        source.taggings.reload
        source.destroy!
        tags_destroyed += 1
      end

      puts "Taggings перевешено: #{taggings_moved}, отброшено дублей: #{taggings_dropped_dupe}"
      puts "Markers перепривязано: #{markers_relinked}"
      puts "Тегов удалено: #{tags_destroyed}"
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  desc <<~DESC
    Для тегов группы from_group с числом taggings в диапазоне
    [min_usage, max_usage] (по умолчанию 1..2) — ищет тег с ТЕМ ЖЕ первым
    словом (без учёта регистра) среди тегов остальных групп (кроме
    from_group/dirty/гео-групп) и, если совпадение однозначное (ровно
    один кандидат), сливает в него — той же безопасной логикой, что
    tags:merge (перевес taggings/markers, reload перед destroy).
    Неоднозначные (>1 кандидата) и не найденные — не трогает, просто
    перечисляет в конце.

    exclude=id1,id2 — явно пропустить конкретные source-теги (ложные
    совпадения, проверенные руками перед прогоном).

    rake tags:merge_by_first_word [from_group=Unsorted] [min_usage=1] [max_usage=2] [exclude=123,456] [dry_run=true]
  DESC
  task :merge_by_first_word do
    dry_run = ENV['dry_run'] == 'true'
    from_group_name = ENV['from_group'] || 'Unsorted'
    min_usage = (ENV['min_usage'] || '1').to_i
    max_usage = (ENV['max_usage'] || '2').to_i
    exclude_ids = (ENV['exclude'] || '').split(',').map(&:to_i).to_set

    from_group = Tag.find_by!(name: from_group_name)
    other_group_names = Tag.where(parent_id: [nil, 0])
      .where.not(name: [from_group_name, 'dirty', 'addressCountry', 'addressRegion', 'addressLocality', 'adm_2'])
      .pluck(:name)
    other_tags = Tag.joins(:parent).where(parent: { name: other_group_names })

    by_first_word = {}
    other_tags.each do |t|
      fw = t.name.downcase.split(/\s+/).first
      next unless fw

      (by_first_word[fw] ||= []) << t
    end

    candidates = from_group.children.select { |t| (min_usage..max_usage).cover?(t.taggings.count) }
    puts "Кандидатов (#{from_group_name}, usage #{min_usage}..#{max_usage}): #{candidates.size}"

    matched_by_target = Hash.new { |h, k| h[k] = [] }
    ambiguous = []
    excluded = []
    no_match = 0

    candidates.each do |t|
      if exclude_ids.include?(t.id)
        excluded << t
        next
      end

      fw = t.name.downcase.split(/\s+/).first
      cands = fw && by_first_word[fw]
      if cands.blank?
        no_match += 1
      elsif cands.size > 1
        ambiguous << [t, cands]
      else
        matched_by_target[cands.first.id] << t
      end
    end

    puts "Однозначных совпадений: #{matched_by_target.values.sum(&:size)} (целевых тегов: #{matched_by_target.size})"
    puts "Неоднозначных (пропущены): #{ambiguous.size}"
    ambiguous.each { |t, cands| puts "  #{t.name.inspect} -> #{cands.map(&:name).join(' / ')}" }
    puts "Исключено вручную (exclude=): #{excluded.size}"
    puts "Без совпадения (остаются как есть): #{no_match}"

    taggings_moved = 0
    taggings_dropped_dupe = 0
    markers_relinked = 0
    tags_destroyed = 0

    ActiveRecord::Base.transaction do
      matched_by_target.each do |target_id, sources|
        target = Tag.find(target_id)

        sources.each do |source|
          source.taggings.each do |tg|
            if Tagging.exists?(tag_id: target.id, taggable_type: tg.taggable_type, taggable_id: tg.taggable_id)
              tg.destroy!
              taggings_dropped_dupe += 1
            else
              tg.update!(tag_id: target.id)
              taggings_moved += 1
            end
          end

          Marker.where(tag_id: source.id).find_each do |m|
            m.update!(tag_id: target.id)
            markers_relinked += 1
          end

          source.taggings.reload
          source.destroy!
          tags_destroyed += 1
        end
      end

      puts "\nTaggings перевешено: #{taggings_moved}, отброшено дублей: #{taggings_dropped_dupe}"
      puts "Markers перепривязано: #{markers_relinked}"
      puts "Тегов удалено: #{tags_destroyed}"
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "\nDRY RUN — откачено, ничего не сохранено" : "\nГотово"
  end

  desc <<~DESC
    Как merge_by_first_word, но матчит по ВХОЖДЕНИЮ слов, не только по
    первому — "Classical Ashtanga" находит "Ashtanga Yoga", а не только
    тег, начинающийся на "Classical" (первым словом обычно идёт
    описательное прилагательное, не само название стиля). Нормализованное
    имя тега-цели (все его слова, порядок не важен) должно целиком
    встречаться среди слов кандидата.

    exclude_groups=Category — группы, которые в словарь НЕ включаем
    (по умолчанию 'Category' — это тип бизнеса, не стиль, случайное
    вхождение слова "studio"/"teacher"/"school" в мусорной фразе стиля
    НЕ значит, что бизнес такого типа — поймано на реальном прогоне).

    rake tags:merge_by_contains [from_group=Unsorted] [exclude_groups=Category] [dry_run=true]
  DESC
  task :merge_by_contains do
    dry_run = ENV['dry_run'] == 'true'
    from_group_name = ENV['from_group'] || 'Unsorted'
    exclude_groups = (ENV['exclude_groups'] || 'Category').split(',')

    normalize = lambda do |s|
      s.to_s.downcase.gsub(/\byoga\b/, ' ').gsub(/[^a-z0-9]+/, ' ').strip.squeeze(' ')
    end

    from_group = Tag.find_by!(name: from_group_name)
    other_group_names = Tag.where(parent_id: [nil, 0])
      .where.not(name: [from_group_name, 'dirty', 'addressCountry', 'addressRegion', 'addressLocality', 'adm_2'] + exclude_groups)
      .pluck(:name)
    other_tags = Tag.joins(:parent).where(parent: { name: other_group_names }).to_a
    dict = other_tags.map { |t| [normalize.call(t.name), t] }.reject { |norm, _| norm.blank? }

    candidates = from_group.children.to_a
    puts "Кандидатов (#{from_group_name}): #{candidates.size}"

    matched = Hash.new { |h, k| h[k] = [] }
    ambiguous = []

    candidates.each do |c|
      words_c = normalize.call(c.name).split(' ')

      hits = dict.select { |norm_t, _t| norm_t.split(' ').all? { |w| words_c.include?(w) } }.map(&:last).uniq
      next if hits.empty?

      hits.size == 1 ? matched[hits.first.id] << c : ambiguous << [c, hits]
    end

    puts "Однозначных совпадений: #{matched.values.sum(&:size)} (целевых тегов: #{matched.size})"
    puts "Неоднозначных (пропущены): #{ambiguous.size}"
    ambiguous.each { |c, hits| puts "  #{c.name.inspect} -> #{hits.map(&:name).join(' / ')}" }

    taggings_moved = 0
    taggings_dropped_dupe = 0
    markers_relinked = 0
    tags_destroyed = 0

    ActiveRecord::Base.transaction do
      matched.each do |target_id, sources|
        target = Tag.find(target_id)

        sources.each do |source|
          source.taggings.each do |tg|
            if Tagging.exists?(tag_id: target.id, taggable_type: tg.taggable_type, taggable_id: tg.taggable_id)
              tg.destroy!
              taggings_dropped_dupe += 1
            else
              tg.update!(tag_id: target.id)
              taggings_moved += 1
            end
          end

          Marker.where(tag_id: source.id).find_each do |m|
            m.update!(tag_id: target.id)
            markers_relinked += 1
          end

          source.taggings.reload
          source.destroy!
          tags_destroyed += 1
        end
      end

      puts "\nTaggings перевешено: #{taggings_moved}, отброшено дублей: #{taggings_dropped_dupe}"
      puts "Markers перепривязано: #{markers_relinked}"
      puts "Тегов удалено: #{tags_destroyed}"
      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "\nDRY RUN — откачено, ничего не сохранено" : "\nГотово"
  end

  desc <<~DESC
    Разбирает csv/unsorted_reclassification.csv (id;name;tag group;tag name
    — ручная разметка Unsorted, один source-тег может маппиться на
    НЕСКОЛЬКО целевых тегов сразу, в отличие от tags:merge/merge_by_*):

    1. Создаёт недостающие ВЕРХНЕУРОВНЕВЫЕ группы (tag group) и недостающие
       целевые теги внутри них.
    2. Если имя целевого тега уже занято ДРУГИМ тегом не из той группы,
       что в файле — не создаёт и не трогает, пропускает эту конкретную
       связь с предупреждением (Tag#name уникален глобально).
    3. Для каждого source id — всем entity, у которых сейчас есть этот
       Unsorted-тег, добавляет Tagging на ВСЕ его целевые теги (не
       перевешивает единственную связь, а копирует — source может
       разъезжаться на несколько целей).
    4. Marker.tag_id source-тега проставляется на ПЕРВЫЙ целевой тег
       (у Marker связь 1:1, это просто "основная" классификация для
       трассировки к исходным данным yogafinder — сама классификация
       entity живёт в Tagging, а не в Marker).
    5. Source-тег удаляется (taggings.reload перед destroy — та же защита
       от бага с dependent: :destroy, что и в остальных tags:merge_*).

    rake tags:apply_reclassification [csv=csv/unsorted_reclassification.csv] [dry_run=true]
  DESC
  task :apply_reclassification do
    require 'csv'

    dry_run = ENV['dry_run'] == 'true'
    csv_path = ENV['csv'] || 'csv/unsorted_reclassification.csv'

    rows = CSV.read(csv_path, headers: true, col_sep: ';')
    by_source = rows.group_by { |r| r['id'].to_i }
    puts "Строк: #{rows.size}, уникальных source id: #{by_source.size}"

    # "Yoga Therapy" как ИМЯ ГРУППЫ (для Individual/PhysioYoga/Structural/
    # TCTSY) конфликтует с уже существующим тегом Tag#105 "Yoga Therapy"
    # (Yoga Special) — те же строки, где "Yoga Therapy" встречается как
    # ЦЕЛЕВОЙ ТЕГ (group=Yoga Special), это разные вещи и Tag#105 не
    # трогаем. Переименовываем только группу.
    GROUP_RENAME = { 'Yoga Therapy' => 'Yoga Therapy Modality' }.freeze
    rename_group = ->(g) { GROUP_RENAME[g] || g }

    # Точечные переименования конкретных (группа,тег) пар — либо тег
    # называется точно так же, как группа, в которую его кладём
    # (Tag#name уникален глобально, группа и её дитя не могут называться
    # одинаково), либо имя занято чем-то совсем из другого домена
    # (Retreat — существующая addressLocality, реальный топоним).
    TARGET_RENAME = {
      ['Bodywork', 'Bodywork'] => 'General Bodywork',
      ['Yoga Philosophy', 'Yoga Philosophy'] => 'General Philosophy',
      ['Event Type', 'Retreat'] => 'Retreat Event'
    }.freeze
    rename_target = ->(g, t) { TARGET_RENAME[[g, t]] || t }

    group_names = rows.map { |r| rename_group.call(r['tag group'].strip) }.uniq
    target_pairs = rows.map { |r| gname = rename_group.call(r['tag group'].strip); [gname, rename_target.call(gname, r['tag name'].strip)] }.uniq
    puts "Целевых групп: #{group_names.size}, целевых (группа,тег) пар: #{target_pairs.size}"

    groups_created = 0
    tags_created = 0
    tags_reused = 0
    conflicts = []
    taggings_added = 0
    markers_updated = 0
    sources_destroyed = 0
    sources_not_found = []

    ActiveRecord::Base.transaction do
      # 1) Снимаем с source-тегов всё, что понадобится ПОЗЖЕ (какие
      # entity помечены, какие Marker на них ссылаются), и сразу удаляем
      # сами source-теги — ДО создания групп/целевых тегов. Иначе часть
      # source-тегов буквально называется так же, как новая группа или
      # новый целевой тег (например Unsorted-тег "Bodywork" и группа
      # "Bodywork" — Tag#name уникален глобально, второе не создать,
      # пока первое существует).
      captured_by_source = {}
      by_source.each do |source_id, _|
        source = Tag.find_by(id: source_id)
        unless source
          sources_not_found << source_id
          next
        end

        taggable_pairs = source.taggings.to_a.map { |tg| [tg.taggable_type, tg.taggable_id] }.uniq
        marker_ids = Marker.where(tag_id: source.id).pluck(:id)
        captured_by_source[source_id] = { taggable_pairs: taggable_pairs, marker_ids: marker_ids }

        source.taggings.reload
        source.destroy!
        sources_destroyed += 1
      end

      # 2) группы
      group_by_name = {}
      group_names.each do |gname|
        group = Tag.find_by(name: gname, parent_id: [nil, 0])
        if group
          group_by_name[gname] = group
        else
          group = Tag.create!(name: gname, parent_id: nil, active: true)
          group_by_name[gname] = group
          groups_created += 1
        end
      end

      # 3) целевые теги (может уже существовать с другим parent — тогда
      # конфликт, пропускаем именно эту пару, не трогаем существующий тег)
      target_tag_by_pair = {}
      target_pairs.each do |gname, tname|
        group = group_by_name[gname]
        existing = Tag.find_by(name: tname)

        if existing
          if existing.parent_id == group.id
            target_tag_by_pair[[gname, tname]] = existing
            tags_reused += 1
          else
            conflicts << "#{tname.inspect} (для группы #{gname.inspect}) уже существует как Tag##{existing.id} в группе #{existing.parent&.name.inspect} — пропущено"
          end
        else
          tag = Tag.create!(name: tname, parent_id: group.id, active: true)
          target_tag_by_pair[[gname, tname]] = tag
          tags_created += 1
        end
      end

      # 4-5) применяем taggings/markers, используя снятые в шаге 1 данные
      by_source.each do |source_id, source_rows|
        captured = captured_by_source[source_id]
        next unless captured

        target_tags = source_rows.filter_map { |r| gname = rename_group.call(r['tag group'].strip); target_tag_by_pair[[gname, rename_target.call(gname, r['tag name'].strip)]] }.uniq
        next if target_tags.empty? # все связи этого source ушли в конфликты

        target_tags.each do |target|
          captured[:taggable_pairs].each do |taggable_type, taggable_id|
            next if Tagging.exists?(tag_id: target.id, taggable_type: taggable_type, taggable_id: taggable_id)

            Tagging.create!(tag_id: target.id, taggable_type: taggable_type, taggable_id: taggable_id)
            taggings_added += 1
          end
        end

        Marker.where(id: captured[:marker_ids]).find_each do |m|
          m.update!(tag_id: target_tags.first.id)
          markers_updated += 1
        end
      end

      puts "\nГрупп создано: #{groups_created}"
      puts "Целевых тегов создано: #{tags_created}, переиспользовано: #{tags_reused}"
      puts "Конфликтов имён (пропущено связей): #{conflicts.size}"
      conflicts.each { |c| puts "  #{c}" }
      puts "Taggings добавлено: #{taggings_added}"
      puts "Markers обновлено: #{markers_updated}"
      puts "Source-тегов удалено: #{sources_destroyed}"
      puts "Source id не найдены в БД: #{sources_not_found.size} #{sources_not_found}" if sources_not_found.any?

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "\nDRY RUN — откачено, ничего не сохранено" : "\nГотово"
  end
end
