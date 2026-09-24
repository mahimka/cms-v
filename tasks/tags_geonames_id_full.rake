# Добивает tags.geonames_id для гео-тегов, у которых ещё нет
# сгенерированной страницы (tags:backfill_geonames_id из
# pages_geonames_id.rake берёт только те, что уже есть в pages.list_tag_id).
# Ad снесли, поэтому мост — снова старый источник (old_yogamela.ads, где
# id это и есть настоящий geonames.org id). Tag#slug для гео-тегов был
# скопирован 1:1 с бывшего Ad#slug (см. tags:copy_ads_slugs), а тот — с
# old_yogamela.ads.slug, с той же дизамбигуацией на коллизии (slug,
# slug-feature_code, slug-feature_code-id — см. geo:import_ads) — поэтому
# сопоставляем в обратную сторону: по slug тега (или его "голой" части,
# если дизамбигуация видна прямо в slug) + ожидаемому feature_code,
# который выводим из группы тега.
class GeonamesIdBackfillConnection < ActiveRecord::Base
  self.abstract_class = true
end

class GeonamesIdBackfillAd < GeonamesIdBackfillConnection
  self.table_name = 'ads'
end

namespace :tags do
  COUNTRY_FEATURE_CODES = %w[PCLI PCLD TERR PCLIX PCLS PCLF PCL PCLH].freeze

  desc "Добить tags.geonames_id для гео-тегов без сгенерированной страницы, через old_yogamela.ads (rake tags:backfill_geonames_id_full db_path=../old_yogamela.com/db/main.db [dry_run=true])"
  task :backfill_geonames_id_full do
    db_path = ENV['db_path']
    raise "Укажи db_path=/path/to/old_yogamela.com/db/main.db" if db_path.blank?
    raise "Файл не найден: #{db_path}" unless File.exist?(db_path)

    dry_run = ENV['dry_run'] == 'true'

    GeonamesIdBackfillConnection.establish_connection(adapter: 'sqlite3', database: db_path)
    source_ad_class = GeonamesIdBackfillAd

    admin_fcs_by_group = {
      'addressCountry' => COUNTRY_FEATURE_CODES,
      'addressRegion' => %w[ADM1],
      'adm_2' => %w[ADM2]
    }
    all_admin_fcs = admin_fcs_by_group.values.flatten
    locality_fcs = source_ad_class.distinct.pluck(:feature_code).compact - all_admin_fcs
    fcs_by_group = admin_fcs_by_group.merge('addressLocality' => locality_fcs)

    group_tags = Tag.where(name: fcs_by_group.keys).index_by(&:name)

    updated = 0
    unresolved = []

    ActiveRecord::Base.transaction do
      fcs_by_group.each do |group_name, expected_fcs|
        group_tag = group_tags[group_name]
        next unless group_tag

        Tag.where(parent_id: group_tag.id, geonames_id: nil).find_each do |tag|
          next if tag.slug.blank?

          candidate = nil
          expected_fcs.each do |fc|
            suffix = "-#{fc.downcase}"
            base = tag.slug.end_with?(suffix) ? tag.slug.delete_suffix(suffix).sub(/-\d+\z/, '') : tag.slug

            found = source_ad_class.find_by(slug: base, feature_code: fc) || source_ad_class.find_by(slug: tag.slug, feature_code: fc)
            if found
              candidate = found
              break
            end
          end

          if candidate
            tag.update_column(:geonames_id, candidate.id)
            updated += 1
          else
            unresolved << "##{tag.id} #{group_name}/#{tag.name} (slug=#{tag.slug})"
          end
        end
      end

      puts "Обновлено: #{updated}"
      puts "Не нашли: #{unresolved.size}"
      unresolved.first(30).each { |u| puts "  #{u}" }
      puts "  ... и ещё #{unresolved.size - 30}" if unresolved.size > 30

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end
end
