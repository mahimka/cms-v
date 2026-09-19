# Перенос listings.{country_id,adm1_id,adm2_id,pp_id} из старого проекта в
# новую схему: ads (локальное зеркало нужного поддерева GeoNames) + теги
# групп addressCountry/addressRegion/adm_2/addressLocality, привязанные к
# ads через Tag#table='ads'/table_id (см. app/models/ad.rb#tags,
# app/models/tag.rb#ad). Тот же приём, что уже применён в kitezilla.com.
class ExternalDbConnection < ActiveRecord::Base
  self.abstract_class = true
end

class SourceListing < ExternalDbConnection
  self.table_name = 'listings'
end

class SourceAd < ExternalDbConnection
  self.table_name = 'ads'
end

def connect_external_db!(path)
  raise "Укажи путь к чужой БД: db_path=/path/to/other/project/db/main.db" if path.blank?
  raise "Файл не найден: #{path}" unless File.exist?(path)

  ExternalDbConnection.establish_connection(adapter: 'sqlite3', database: path)
end

namespace :geo do
  desc "Создать корневые группы тегов addressCountry/addressRegion/addressLocality/adm_2 (rake geo:create_groups)"
  task :create_groups do
    %w[addressCountry addressRegion addressLocality adm_2].each do |name|
      tag = Tag.find_or_create_by!(name: name)
      puts "Tag ##{tag.id} #{tag.name}"
    end
  end

  desc "Скопировать в ads только нужное поддерево GeoNames (то, на что ссылаются listings.country_id/adm1_id/adm2_id/pp_id + их предки) (rake geo:import_ads db_path=../old_yogamela.com/db/main.db [dry_run=true])"
  task :import_ads do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    referenced_ids = %i[country_id adm1_id adm2_id pp_id].flat_map do |col|
      SourceListing.where.not(col => nil).distinct.pluck(col)
    end.uniq

    puts "Уникальных id, на которые ссылаются listings: #{referenced_ids.size}"

    # Расширяем набор предками (ancestry вида "/id1/id2/") — иначе у
    # скопированных ads будут дырки в цепочке parent_id.
    needed_ids = referenced_ids.to_set
    found_ads = {}

    queue = referenced_ids.dup
    until queue.empty?
      id = queue.shift
      next if found_ads.key?(id)

      ad = SourceAd.find_by(id: id)
      found_ads[id] = ad
      next unless ad

      ad.ancestry.to_s.split('/').compact_blank.map(&:to_i).each do |ancestor_id|
        next if needed_ids.include?(ancestor_id)

        needed_ids << ancestor_id
        queue << ancestor_id
      end
    end

    missing_referenced = referenced_ids.reject { |id| found_ads[id] }
    puts "Из них найдено локально в старой ads: #{found_ads.values.compact.size} записей (включая предков, всего id в поддереве: #{needed_ids.size})"
    puts "Не найдено локально (потребуется geo:locality_from_address для pp, если это pp_id): #{missing_referenced.size}"

    ordered = found_ads.values.compact.sort_by { |a| a.ancestry.to_s.count('/') }

    id_map = {}
    created = 0
    reused = 0

    ActiveRecord::Base.transaction do
      ordered.each do |old_ad|
        # slug один в один не годится как ключ идемпотентности — у
        # исходного geonames-зеркала старого проекта город и совпадающий
        # с ним по имени регион/страна (Milan ADM2 и Milan PPLA, London
        # PPLC и London PPL и т.п.) могут иметь ОДИНАКОВЫЙ slug при
        # РАЗНОМ feature_code. Ключ реюза — (slug, feature_code); при
        # занятом slug с другим feature_code — берём slug с суффиксом.
        existing = Ad.find_by(slug: old_ad.slug, feature_code: old_ad.feature_code)
        if existing
          id_map[old_ad.id] = existing.id
          reused += 1
          next
        end

        parent_old_id = old_ad.ancestry.to_s.split('/').compact_blank.last&.to_i
        parent_id = parent_old_id ? id_map[parent_old_id] : nil

        # Несколько записей в источнике могут делить и slug, И feature_code
        # одновременно (например у "cambridge" в needed-поддереве три PPL) —
        # суффикса по feature_code одного может не хватить, добираем id.
        slug = old_ad.slug
        slug = "#{old_ad.slug}-#{old_ad.feature_code.to_s.downcase}" if Ad.exists?(slug: slug)
        slug = "#{old_ad.slug}-#{old_ad.feature_code.to_s.downcase}-#{old_ad.id}" if Ad.exists?(slug: slug)

        ad = Ad.new(
          name: old_ad.name,
          slug: slug,
          feature_code: old_ad.feature_code,
          country_code: old_ad.country_code,
          admin1_code: old_ad.admin1_code,
          admin2_code: old_ad.admin2_code,
          population: old_ad.population,
          latitude: old_ad.latitude,
          longitude: old_ad.longitude,
          timezone: old_ad.timezone,
          short: old_ad.short,
          active: old_ad.listed && old_ad.ready
        )
        ad.parent_id = parent_id if parent_id
        ad.save!

        id_map[old_ad.id] = ad.id
        created += 1
      end

      puts "ads: создано #{created}, переиспользовано по slug #{reused}"

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Ad.count теперь #{Ad.count}"
  end

  desc "Создать/найти дочерний Tag (table='ads') под нужной группой для каждого скопированного Ad (rake geo:tag_from_ads [dry_run=true])"
  task :tag_from_ads do
    dry_run = ENV['dry_run'] == 'true'

    country_group = Tag.find_by!(name: 'addressCountry')
    region_group = Tag.find_by!(name: 'addressRegion')
    adm2_group = Tag.find_by!(name: 'adm_2')
    locality_group = Tag.find_by!(name: 'addressLocality')

    created = 0
    reused = 0
    renamed = []

    ActiveRecord::Base.transaction do
      Ad.find_each do |ad|
        existing = Tag.find_by(table: 'ads', table_id: ad.id)
        if existing
          reused += 1
          next
        end

        group = if Ad::COUNTRY_FEATURE_CODES.include?(ad.feature_code)
                  country_group
                elsif ad.feature_code == 'ADM1'
                  region_group
                elsif ad.feature_code == 'ADM2'
                  adm2_group
                else
                  locality_group
                end

        # name зависает в бесконечном цикле, если даже "base (feature_code)"
        # уже занят — бывает, когда несколько ads делят и name, и
        # feature_code (например три разных "Cambridge" уровня PPL в
        # разных странах) — тогда докидываем ad.id, он всегда свободен.
        base_name = ad.display_name
        name = base_name
        name = "#{base_name} (#{ad.feature_code})" if Tag.exists?(name: name)
        name = "#{base_name} (#{ad.feature_code} ##{ad.id})" if Tag.exists?(name: name)
        renamed << "#{base_name} -> #{name}" if name != base_name

        # slug тоже в GEONAMES_SYNCED_FIELDS — берём из ad.slug сразу при
        # создании (protected_fields_unchanged_if_from_ads не мешает: она
        # только на update, не на create). Ad#slug уникален только внутри
        # ads, Tag#slug — по всей таблице, поэтому на коллизии докидываем id.
        slug = ad.slug.presence
        slug = "#{ad.slug}-#{ad.id}" if slug && Tag.exists?(slug: slug)

        Tag.create!(name: name, slug: slug, parent_id: group.id, table: 'ads', table_id: ad.id)
        created += 1
      end

      puts "Гео-тегов создано: #{created}, переиспользовано: #{reused}"
      puts "Переименовано из-за коллизии имени: #{renamed.join(', ')}" if renamed.any?

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  # Формат "<улица> <Город>, <штат/провинция> ZIP" — почти все ~871
  # непокрытых pp_id (808 US + 28 CA из 871) соответствуют ему; остальные
  # страны/произвольный текст сюда не суём — слишком разные форматы,
  # риск угадать неверно выше пользы, такие просто идут в лог на разбор.
  STREET_STOPWORDS = %w[
    st ave blvd rd dr ln way ct pl pkwy hwy ste suite unit apt fl bldg
    room rm street avenue road drive lane boulevard court place parkway
    highway building floor n s e w ne nw se sw north south east west
    pike turnpike broadway circle cir trail trl terrace ter row square
    sq plaza path
  ].freeze

  def extract_locality_from_address(address, parts)
    return nil if address.blank?

    segment = parts.size >= 2 ? parts[-2] : parts[0]
    return nil if segment.blank?

    words = []
    segment.strip.split(/\s+/).reverse_each do |raw|
      break if raw =~ /\d/
      # Одна буква почти всегда обозначение suite/unit/apt ("Apt C",
      # "Suite F"), а не начало названия города.
      break if raw.length <= 1

      clean = raw.gsub(/[^\p{L}.'-]/, '').delete('.')
      break if clean.blank?
      break if STREET_STOPWORDS.include?(clean.downcase)
      break unless clean =~ /\A\p{Lu}/

      # Если следующее (ближе к началу строки) слово повторяет уже
      # найденное — это дубль в духе "Bloomsburg Bloomsburg" в самом
      # исходном адресе, не расширяем им название дальше.
      break if words.first&.casecmp?(clean)

      words.unshift(clean)
      break if words.size >= 3
    end

    words.any? ? words.join(' ') : nil
  end

  desc "Для listings с pp_id вне скопированного поддерева ads — вывести locality из адреса (только US/CA), создать Tag под addressLocality без table/table_id (rake geo:locality_from_address db_path=../old_yogamela.com/db/main.db [dry_run=true])"
  task :locality_from_address do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    locality_group = Tag.find_by!(name: 'addressLocality')

    # "Не покрыт" — если для pp_id нет Ad с таким slug в уже скопированной
    # ads, т.е. повторяем ту же проверку, что и geo:import_ads, а не
    # полагаемся на какое-то промежуточное состояние между задачами.
    pp_ids = SourceListing.where.not(pp_id: nil).distinct.pluck(:pp_id)
    old_slug_by_pp_id = SourceAd.where(id: pp_ids).pluck(:id, :slug).to_h
    existing_ad_slugs = Ad.pluck(:slug).to_set

    gap_listings = SourceListing.where.not(pp_id: nil).select do |l|
      slug = old_slug_by_pp_id[l.pp_id]
      slug.nil? || !existing_ad_slugs.include?(slug)
    end

    puts "Listings с непокрытым pp_id: #{gap_listings.size}"

    # US/CA определяем по стране самого listing (id страны и её
    # country_code лежат в старой ads), а не по гипотезам о формате
    # ancestry для корневых записей.
    country_code_by_id = SourceAd.where(id: SourceListing.where.not(country_id: nil).distinct.pluck(:country_id)).pluck(:id, :country_code).to_h
    created = 0
    reused = 0
    unresolved = []

    ActiveRecord::Base.transaction do
      gap_listings.each do |l|
        unless %w[US CA].include?(country_code_by_id[l.country_id])
          unresolved << "##{l.id} #{l.name}: не US/CA (country_id=#{l.country_id.inspect}), пропуск"
          next
        end

        # Часть адресов не имеет запятой перед zip/почтовым кодом
        # ("Sedona 86336", "Pembroke K8A 7T6") — без этого зачистка не
        # доходит до имени города, упираясь в цифры с конца строки.
        cleaned_address = l.address.to_s
          .sub(/\s+\d{5}(-\d{4})?\s*\z/, '')
          .sub(/\s+[A-Za-z]\d[A-Za-z]\s*\d[A-Za-z]\d\s*\z/, '')
        parts = cleaned_address.split(',').map(&:strip)
        city = extract_locality_from_address(cleaned_address, parts)

        unless city
          unresolved << "##{l.id} #{l.name}: не удалось разобрать address=#{l.address.inspect}"
          next
        end

        # Tag#name уникален глобально — city может совпасть с уже занятым
        # именем (реальный geo-тег с тем же названием в другой стране,
        # либо другая, ранее уже задизамбигуированная запись этого же
        # цикла). Перебираем "city (2)", "city (3)"... пока не найдём
        # либо свою же ранее созданную запись (reuse), либо свободное имя.
        candidate = city
        n = 1
        tag = nil
        loop do
          same_parent = Tag.find_by(name: candidate, parent_id: locality_group.id)
          if same_parent
            tag = same_parent
            reused += 1
            break
          end

          unless Tag.exists?(name: candidate)
            tag = Tag.create!(name: candidate, parent_id: locality_group.id)
            created += 1
            break
          end

          n += 1
          candidate = "#{city} (#{n})"
        end
      end

      puts "Tag создано: #{created}, переиспользовано: #{reused}, не разобрано: #{unresolved.size}"

      raise ActiveRecord::Rollback if dry_run
    end

    if unresolved.any?
      puts "--- разобрать вручную ---"
      puts unresolved.join("\n")
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end
end
