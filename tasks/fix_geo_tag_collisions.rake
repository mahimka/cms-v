# geo:import_ads до фикса reuse-ключа (slug -> slug+feature_code) молча
# схлопывал в одну ads-запись город и административную единицу с тем же
# slug в источнике (Milan ADM2 и Milan PPLA, London PPLC и London PPL и
# т.д. — 167 таких пар/групп в нужном поддереве). geo:import_ads уже
# перезапущен и досоздал 188 недостающих ads, geo:tag_from_ads — их теги.
# Эта задача пересчитывает и чинит фактическую разметку entity: только
# гео-теги (table='ads', родитель — одна из 4 групп), только там, где
# требуется — ничего не трогает у topical-тегов и адресного fallback.
namespace :entities do
  desc "Досчитать/поправить ads-геотеги у Entity после фикса slug-коллизий в geo:import_ads (rake entities:fix_geo_tag_collisions db_path=../old_yogamela.com/db/main.db [dry_run=true])"
  task :fix_geo_tag_collisions do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    schema = Schema.find_by!(name: 'LocalBusiness')

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

    # (name, feature_code, latitude, longитude) как ключ ненадёжен — в
    # исходной old_yogamela.ads попадаются настоящие дубли одного и того
    # же места (тот же name/feature_code, но чуть другие lat/lng — два
    # разных geonameid на один Cambridge, ON). Вместо угадывания по
    # координатам повторяем ТОЧНО ту же логику, что и geo:import_ads при
    # создании slug (slug, затем slug-feature_code, затем
    # slug-feature_code-id) — так резолвится единообразно.
    new_ad_by_slug_and_fc = Ad.pluck(:slug, :feature_code, :id)
      .each_with_object({}) { |(slug, fc, id), h| h[[slug, fc]] = id }

    old_id_to_new_ad_id = {}
    found_ads.each do |old_id, old_ad|
      next unless old_ad

      fc = old_ad.feature_code
      candidates = [
        old_ad.slug,
        "#{old_ad.slug}-#{fc.to_s.downcase}",
        "#{old_ad.slug}-#{fc.to_s.downcase}-#{old_ad.id}"
      ]
      new_ad_id = candidates.map { |slug| new_ad_by_slug_and_fc[[slug, fc]] }.compact.first
      old_id_to_new_ad_id[old_id] = new_ad_id if new_ad_id
    end

    unresolved_old_ids = found_ads.keys.select { |id| found_ads[id] && !old_id_to_new_ad_id[id] }
    puts "old ad id без соответствия в новой ads (не должно быть после geo:import_ads): #{unresolved_old_ids.size}"

    geo_tag_id_by_ad_id = Tag.where(table: 'ads').pluck(:table_id, :id).to_h
    geo_group_ids = Tag.where(name: %w[addressCountry addressRegion addressLocality adm_2]).pluck(:id)

    listings_by_key = Hash.new { |h, k| h[k] = [] }
    SourceListing.find_each { |l| listings_by_key[[l.name, l.address]] << l }

    entity_id_by_key = Entity.where(schema: schema).pluck(:name, :address, :id)
      .each_with_object({}) { |(n, a, id), h| h[[n, a]] = id }

    current_geo_taggings_by_entity = Tagging.joins(:tag)
      .where(taggable_type: 'Entity', tags: { table: 'ads' })
      .where(tags: { parent_id: geo_group_ids })
      .pluck(:taggable_id, :tag_id)
      .each_with_object(Hash.new { |h, k| h[k] = Set.new }) { |(eid, tid), h| h[eid] << tid }

    added = 0
    removed = 0
    entities_touched = 0
    entities_missing = []

    ActiveRecord::Base.transaction do
      listings_by_key.each do |key, listings|
        entity_id = entity_id_by_key[key]
        unless entity_id
          entities_missing << key.first
          next
        end

        correct_tag_ids = Set.new
        listings.each do |l|
          [l.country_id, l.adm1_id, l.adm2_id, l.pp_id].each do |gid|
            next unless gid

            new_ad_id = old_id_to_new_ad_id[gid]
            tag_id = new_ad_id && geo_tag_id_by_ad_id[new_ad_id]
            correct_tag_ids << tag_id if tag_id
          end
        end

        current_tag_ids = current_geo_taggings_by_entity[entity_id] || Set.new

        to_add = correct_tag_ids - current_tag_ids
        to_remove = current_tag_ids - correct_tag_ids
        next if to_add.empty? && to_remove.empty?

        to_add.each do |tid|
          next if Tagging.exists?(taggable_type: 'Entity', taggable_id: entity_id, tag_id: tid)

          Tagging.create!(taggable_type: 'Entity', taggable_id: entity_id, tag_id: tid)
          added += 1
        end

        to_remove.each do |tid|
          Tagging.where(taggable_type: 'Entity', taggable_id: entity_id, tag_id: tid).destroy_all
          removed += 1
        end

        entities_touched += 1
      end

      puts "Entity затронуто: #{entities_touched}"
      puts "Taggings добавлено: #{added}, удалено (были на неверном уровне): #{removed}"
      puts "listings без соответствующего Entity: #{entities_missing.size}" if entities_missing.any?

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end
end
