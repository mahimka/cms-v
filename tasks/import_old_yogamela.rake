# Перенос old_yogamela.com -> yogamela.com: listings -> entities (schema
# LocalBusiness), их теги/гео-теги, listings.phone -> entity.details,
# затем profiles/links поверх уже созданных entities. Каждая задача сама
# по себе идемпотентна и может быть перезапущена — Entity ищется/создаётся
# по естественному ключу (name, address), т.к. у old_yogamela.listings
# latitude/longitude пустые у всех строк (не геокодировано), а у Entity
# нет отдельной колонки под внешний id.
class ExternalDbConnection < ActiveRecord::Base
  self.abstract_class = true
end

class SourceListing < ExternalDbConnection
  self.table_name = 'listings'
end

class SourceAd < ExternalDbConnection
  self.table_name = 'ads'
end

class SourceTag < ExternalDbConnection
  self.table_name = 'tags'
end

class SourceTagging < ExternalDbConnection
  self.table_name = 'taggings'
end

class SourceProfile < ExternalDbConnection
  self.table_name = 'profiles'
end

class SourceLink < ExternalDbConnection
  self.table_name = 'links'
end

def connect_external_db!(path)
  raise "Укажи путь к чужой БД: db_path=/path/to/other/project/db/main.db" if path.blank?
  raise "Файл не найден: #{path}" unless File.exist?(path)

  ExternalDbConnection.establish_connection(adapter: 'sqlite3', database: path)
end

# entities.rake учит новую ads в geo:import_ads/geo:tag_from_ads/
# geo:locality_from_address — здесь резолвим listing -> готовый гео-тег
# по тому же принципу (slug старого ad = slug нового ad), без повторного
# похода в geonames.
def resolve_geo_tag_id(old_id, old_ad_slug_by_id, new_ad_id_by_slug, geo_tag_id_by_ad_id)
  return nil unless old_id

  slug = old_ad_slug_by_id[old_id]
  return nil unless slug

  new_ad_id = new_ad_id_by_slug[slug]
  return nil unless new_ad_id

  geo_tag_id_by_ad_id[new_ad_id]
end

# geo:locality_from_address создаёт "city", а при коллизии имени с уже
# занятым где-то ещё (например реальным geo-тегом) — "city (2)", "city
# (3)"... под addressLocality (см. STREET_STOPWORDS/loop в geo_import.rake).
# Здесь по тому же исходному city повторяем тот же перебор кандидатов,
# чтобы найти именно тот тег, а не только "city" в чистом виде.
def resolve_locality_tag(city, locality_group)
  (1..5).each do |n|
    candidate = n == 1 ? city : "#{city} (#{n})"
    tag = Tag.find_by(name: candidate, parent_id: locality_group.id)
    return tag if tag
  end
  nil
end

namespace :entities do
  desc "listings -> entities (schema LocalBusiness), с тегами (topical+гео) и phone->details (rake entities:import_from_listings db_path=../old_yogamela.com/db/main.db [dry_run=true])"
  task :import_from_listings do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    schema = Schema.find_by!(name: 'LocalBusiness')
    phone_label = Label.find_by!(name: 'phone')
    locality_group = Tag.find_by!(name: 'addressLocality')

    old_tag_name_by_id = SourceTag.pluck(:id, :name).to_h
    new_tag_id_by_name = Tag.pluck(:name, :id).to_h
    old_taggings_by_listing = SourceTagging.where.not(listing_id: nil).pluck(:listing_id, :tag_id)
      .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(lid, tid), h| h[lid] << tid }

    old_ad_slug_by_id = SourceAd.pluck(:id, :slug).to_h
    new_ad_id_by_slug = Ad.pluck(:slug, :id).to_h
    geo_tag_id_by_ad_id = Tag.where(table: 'ads').pluck(:table_id, :id).to_h
    country_code_by_old_ad_id = SourceAd.pluck(:id, :country_code).to_h

    entities_created = 0
    entities_reused = 0
    taggings_added = 0
    details_added = 0
    locality_fallback_used = 0
    locality_fallback_missing = 0

    ActiveRecord::Base.transaction do
      SourceListing.find_each do |l|
        entity = Entity.find_by(name: l.name, address: l.address)
        if entity
          entities_reused += 1
        else
          entity = Entity.create!(
            name: l.name,
            address: l.address,
            latitude: l.latitude,
            longitude: l.longitude,
            schema: schema,
            generate_pages: l.listed && l.ready
          )
          entities_created += 1
        end

        tag_ids = []

        (old_taggings_by_listing[l.id] || []).each do |old_tag_id|
          name = old_tag_name_by_id[old_tag_id]
          new_id = name && new_tag_id_by_name[name]
          tag_ids << new_id if new_id
        end

        [l.country_id, l.adm1_id, l.adm2_id, l.pp_id].each do |gid|
          tag_id = resolve_geo_tag_id(gid, old_ad_slug_by_id, new_ad_id_by_slug, geo_tag_id_by_ad_id)
          tag_ids << tag_id if tag_id
        end

        # pp_id вне скопированного поддерева ads — тот же адресный fallback,
        # что уже прогнан в geo:locality_from_address (теги там уже
        # созданы), здесь только находим нужный по имени.
        if l.pp_id && !resolve_geo_tag_id(l.pp_id, old_ad_slug_by_id, new_ad_id_by_slug, geo_tag_id_by_ad_id)
          country_code = country_code_by_old_ad_id[l.country_id]
          if %w[US CA].include?(country_code)
            cleaned_address = l.address.to_s
              .sub(/\s+\d{5}(-\d{4})?\s*\z/, '')
              .sub(/\s+[A-Za-z]\d[A-Za-z]\s*\d[A-Za-z]\d\s*\z/, '')
            parts = cleaned_address.split(',').map(&:strip)
            city = extract_locality_from_address(cleaned_address, parts)
            fallback_tag = city && resolve_locality_tag(city, locality_group)

            if fallback_tag
              tag_ids << fallback_tag.id
              locality_fallback_used += 1
            else
              locality_fallback_missing += 1
            end
          else
            locality_fallback_missing += 1
          end
        end

        tag_ids.uniq.each do |tag_id|
          next if entity.taggings.exists?(tag_id: tag_id)

          entity.taggings.create!(tag_id: tag_id)
          taggings_added += 1
        end

        if l.phone.present?
          detail = Detail.find_or_initialize_by(detailable: entity, label: phone_label)
          unless detail.persisted?
            detail.value = l.phone
            detail.save!
            details_added += 1
          end
        end
      end

      puts "Entity создано: #{entities_created}, переиспользовано (дубли name+address в источнике): #{entities_reused}"
      puts "Taggings добавлено: #{taggings_added}"
      puts "Details (phone) добавлено: #{details_added}"
      puts "Адресный fallback для addressLocality — применён: #{locality_fallback_used}, не нашли тег: #{locality_fallback_missing}"

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Entity.count теперь #{Entity.count}"
  end
end

namespace :profiles do
  desc "old_yogamela.profiles -> profiles, привязка к Entity по (name,address) листинга, site=YogaFinder (rake profiles:import_from_old db_path=../old_yogamela.com/db/main.db [dry_run=true])"
  task :import_from_old do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    site = Site.find_or_create_by!(name: 'YogaFinder') do |s|
      s.domain = 'yogafinder.com'
      s.url = 'https://yogafinder.com/'
    end

    listings_by_id = SourceListing.pluck(:id, :name, :address).each_with_object({}) { |(id, name, address), h| h[id] = [name, address] }
    entity_id_by_key = Entity.where(schema: Schema.find_by(name: 'LocalBusiness')).pluck(:name, :address, :id)
      .each_with_object({}) { |(name, address, id), h| h[[name, address]] = id }

    created = 0
    reused = 0
    skipped_no_listing = 0
    skipped_no_entity = 0

    ActiveRecord::Base.transaction do
      SourceProfile.find_each do |p|
        key = p.listing_id && listings_by_id[p.listing_id]
        unless key
          skipped_no_listing += 1
          next
        end

        entity_id = entity_id_by_key[key]
        unless entity_id
          skipped_no_entity += 1
          next
        end

        existing = Profile.find_by(profileable_type: 'Entity', profileable_id: entity_id, url: p.url)
        if existing
          reused += 1
          next
        end

        Profile.create!(
          profileable_type: 'Entity',
          profileable_id: entity_id,
          site_id: site.id,
          url: p.url,
          alive: p.active.nil? ? true : p.active,
          redirected: p.redirects_to_url.present?,
          redirected_to: p.redirects_to_url,
          status: p.response,
          scraped_at: p.parsed_at
        )
        created += 1
      end

      puts "Profile создано: #{created}, переиспользовано: #{reused}"
      puts "Пропущено (у profile нет listing_id / listing не найден): #{skipped_no_listing}"
      puts "Пропущено (для listing нет соответствующего Entity — не должно случаться после entities:import_from_listings): #{skipped_no_entity}"

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Profile.count теперь #{Profile.count}"
  end
end

namespace :links do
  LINK_LABEL_BY_HOST = {
    'facebook.com' => 'facebook',
    'instagram.com' => 'instagram',
    'youtube.com' => 'youtube',
    'youtu.be' => 'youtube',
    'twitter.com' => 'x',
    'x.com' => 'x',
    'linkedin.com' => 'linkedin'
  }.freeze

  def link_label_name_for_url(url)
    host = URI.parse(url).host.to_s.downcase.sub(/\Awww\./, '')
    LINK_LABEL_BY_HOST.each { |domain, label| return label if host == domain || host.end_with?(".#{domain}") }
    'website'
  rescue URI::InvalidURIError
    'website'
  end

  desc "old_yogamela.links -> links, label по домену (facebook/instagram/youtube/x/linkedin/website), привязка к Entity по listing (name,address) (rake links:import_from_old db_path=../old_yogamela.com/db/main.db [dry_run=true])"
  task :import_from_old do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    listings_by_id = SourceListing.pluck(:id, :name, :address).each_with_object({}) { |(id, name, address), h| h[id] = [name, address] }
    entity_id_by_key = Entity.where(schema: Schema.find_by(name: 'LocalBusiness')).pluck(:name, :address, :id)
      .each_with_object({}) { |(name, address, id), h| h[[name, address]] = id }
    label_id_by_name = Label.where(name: LINK_LABEL_BY_HOST.values.uniq + ['website']).pluck(:name, :id).to_h

    created = 0
    reused = 0
    skipped_no_listing = 0
    skipped_no_entity = 0
    skipped_blank_url = 0
    by_label = Hash.new(0)

    ActiveRecord::Base.transaction do
      SourceLink.find_each do |l|
        if l.url.blank?
          skipped_blank_url += 1
          next
        end

        key = l.listing_id && listings_by_id[l.listing_id]
        unless key
          skipped_no_listing += 1
          next
        end

        entity_id = entity_id_by_key[key]
        unless entity_id
          skipped_no_entity += 1
          next
        end

        existing = Link.find_by(linkable_type: 'Entity', linkable_id: entity_id, url: l.url)
        if existing
          reused += 1
          next
        end

        label_name = link_label_name_for_url(l.url)
        by_label[label_name] += 1

        Link.create!(
          linkable_type: 'Entity',
          linkable_id: entity_id,
          label_id: label_id_by_name[label_name],
          url: l.url,
          active: l.active.nil? ? true : l.active
        )
        created += 1
      end

      puts "Link создано: #{created}, переиспользовано: #{reused}"
      puts "По label: #{by_label.map { |k, v| "#{k}=#{v}" }.join(', ')}"
      puts "Пропущено (пустой url): #{skipped_blank_url}"
      puts "Пропущено (нет listing_id / listing не найден — известная проблема ссылок на несуществующий listing_id в источнике): #{skipped_no_listing}"
      puts "Пропущено (для listing нет Entity): #{skipped_no_entity}"

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Link.count теперь #{Link.count}"
  end
end
