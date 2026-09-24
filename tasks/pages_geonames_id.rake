# pages.geonames_id — настоящий geonames.org id (то, чем был id в
# old_yogamela.ads — локальном зеркале geonames.org, у нас же
# `ads.id` — обычный auto-increment, geonames.org id туда не переносился,
# только slug/имя/коды). Восстанавливаем тем же путём, что и
# entities:fix_geo_tag_collisions (см. fix_geo_tag_collisions.rake) —
# для каждого старого ad пробуем те же кандидаты slug (slug,
# slug-feature_code, slug-feature_code-id — см. geo:import_ads), находим
# по ним текущий Ad (по (slug, feature_code)), через Tag(table='ads',
# table_id: ad.id) — тег, через Tag#taggings/Page#list_tag_id — страницы.
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

namespace :pages do
  desc "Заполнить pages.geonames_id для гео-страниц (country/region/locality/adm_2) настоящим geonames.org id из источника (rake pages:backfill_geonames_id db_path=../old_yogamela.com/db/main.db [dry_run=true])"
  task :backfill_geonames_id do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    # Тот же BFS, что и в geo:import_ads/entities:fix_geo_tag_collisions —
    # нужное поддерево (id, на которые реально ссылаются listings, + их
    # предки по ancestry).
    referenced_ids = %i[country_id adm1_id adm2_id pp_id].flat_map do |col|
      SourceListing.where.not(col => nil).distinct.pluck(col)
    end.uniq

    found_ads = {}
    queue = referenced_ids.dup
    until queue.empty?
      id = queue.shift
      next if found_ads.key?(id)

      ad = SourceAd.find_by(id: id)
      found_ads[id] = ad
      next unless ad

      ad.ancestry.to_s.split('/').compact_blank.map(&:to_i).each do |ancestor_id|
        next if found_ads.key?(ancestor_id)

        queue << ancestor_id
      end
    end

    new_ad_by_slug_and_fc = Ad.pluck(:slug, :feature_code, :id).each_with_object({}) { |(slug, fc, id), h| h[[slug, fc]] = id }
    geo_tag_id_by_ad_id = Tag.where(table: 'ads').pluck(:table_id, :id).to_h

    # old_ad.id (настоящий geonames.org id) -> geo_tag_id
    geonames_id_by_tag_id = {}

    found_ads.each_value do |old_ad|
      next unless old_ad

      fc = old_ad.feature_code
      candidates = [
        old_ad.slug,
        "#{old_ad.slug}-#{fc.to_s.downcase}",
        "#{old_ad.slug}-#{fc.to_s.downcase}-#{old_ad.id}"
      ]
      new_ad_id = candidates.map { |slug| new_ad_by_slug_and_fc[[slug, fc]] }.compact.first
      next unless new_ad_id

      tag_id = geo_tag_id_by_ad_id[new_ad_id]
      next unless tag_id

      geonames_id_by_tag_id[tag_id] = old_ad.id
    end

    puts "Гео-тегов с найденным geonames.org id: #{geonames_id_by_tag_id.size} из #{geo_tag_id_by_ad_id.size}"

    updated = 0
    skipped_no_page = 0

    ActiveRecord::Base.transaction do
      geonames_id_by_tag_id.each do |tag_id, geonames_id|
        n = Page.where(list_tag_id: tag_id).update_all(geonames_id: geonames_id)
        skipped_no_page += 1 if n.zero?
        updated += n
      end

      puts "Обновлено страниц: #{updated}"
      puts "Тегов без соответствующей страницы (ещё не сгенерирована): #{skipped_no_page}"

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end
end

namespace :tags do
  # Ad (и Tag#table/table_id) с тех пор снесли — тем же путём, что у
  # pages:backfill_geonames_id (через старую ads), уже не пройти. Но
  # pages.geonames_id уже заполнен и однозначно завязан на свой тег через
  # list_tag_id — выводим tags.geonames_id прямо из него, без внешней БД.
  desc "Заполнить tags.geonames_id из уже проставленного pages.geonames_id (через list_tag_id) (rake tags:backfill_geonames_id [dry_run=true])"
  task :backfill_geonames_id do
    dry_run = ENV['dry_run'] == 'true'

    pairs = Page.where.not(geonames_id: nil).where.not(list_tag_id: nil)
      .distinct.pluck(:list_tag_id, :geonames_id)

    updated = 0
    conflicts = []

    ActiveRecord::Base.transaction do
      pairs.each do |tag_id, geonames_id|
        tag = Tag.find(tag_id)
        if tag.geonames_id.present? && tag.geonames_id != geonames_id
          conflicts << "##{tag_id} #{tag.name}: уже #{tag.geonames_id}, из страниц пришло #{geonames_id}"
          next
        end

        tag.update_column(:geonames_id, geonames_id)
        updated += 1
      end

      puts "Тегов обновлено: #{updated}"
      puts "Конфликтов (разные geonames_id у одного тега с разных страниц): #{conflicts.size}"
      conflicts.each { |c| puts "  #{c}" }

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end
end
