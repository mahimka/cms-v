require 'csv'

namespace :import do
  desc "Импорт csv/trieste_hotels_all_property_types.csv как Profile (tripadvisor.com) + Entity (LodgingBusiness) (rake import:trieste_hotels)"
  task :trieste_hotels do
    site = Site.find_by!(domain: 'tripadvisor.com')
    schema = Schema.find_by!(name: 'LodgingBusiness')

    country_tag = Tag.find_by!(name: 'Italy')
    locality_tag = Tag.find_by!(name: 'Trieste')
    lodging_group = Tag.find_by!(name: 'Organization:LodgingBusiness')
    base_type_tag = lodging_group.children.find_by!(name: 'LodgingBusiness')
    base_tags = [country_tag, locality_tag, base_type_tag]

    # CSV-значение property_types -> имя тега в группе Organization:LodgingBusiness.
    # Уникальные токены в файле сопоставлены вручную по смыслу (Pensions —
    # европейский синоним гостевого дома/B&B; Condos/Cottage/Villa — типы
    # аренды жилья на отдых). То, чему нет соответствия, получает новый тег
    # "_ta_<токен>" прямо в этой же группе (см. resolve_type_tag).
    TYPE_TAG_NAMES = {
      'Hotels' => 'Hotel',
      'B&Bs & Inns' => 'BedAndBreakfast',
      'Hostels' => 'Hostel',
      'Campgrounds' => 'Campground',
      'Pensions' => 'BedAndBreakfast',
      'Condos' => 'VacationRental',
      'Cottage' => 'VacationRental',
      'Villa' => 'VacationRental'
    }.freeze

    created_tags = []

    resolve_type_tag = lambda do |token|
      mapped_name = TYPE_TAG_NAMES[token]
      tag = lodging_group.children.find_by(name: mapped_name) if mapped_name
      tag ||= lodging_group.children.find_by(name: token)
      tag ||= lodging_group.children.find_by(name: "_ta_#{token}")
      if tag.nil?
        tag = lodging_group.children.create!(name: "_ta_#{token}", active: true)
        created_tags << tag.name
      end
      tag
    end

    file = File.expand_path('../csv/trieste_hotels_all_property_types.csv', __dir__)

    created = 0
    skipped_existing = 0

    CSV.foreach(file, headers: true, liberal_parsing: true) do |row|
      name = row['name']&.strip
      url = row['url']&.strip
      next if name.blank? || url.blank?

      if Profile.exists?(site: site, url: url)
        skipped_existing += 1
        next
      end

      types = row['property_types'].to_s.split(',').map(&:strip).reject(&:blank?)
      type_tags = types.map { |token| resolve_type_tag.call(token) }

      entity = Entity.create!(name: name, schema: schema, active: true)
      (base_tags + type_tags).uniq.each do |tag|
        entity.taggings.where(tag_id: tag.id).first_or_create!
      end

      Profile.create!(
        site: site,
        url: url,
        profileable: entity,
        title: name,
        rating: row['rating'].presence&.to_f,
        review_count: row['reviews_count'].presence&.to_i,
        notes: row['property_types']
      )

      created += 1
      puts "  + #{name} (entity ##{entity.id})"
    end

    puts "Готово: создано #{created}, пропущено (уже есть Profile с этим url) #{skipped_existing}"
    puts "Новые теги в Organization:LodgingBusiness: #{created_tags.uniq.join(', ')}" if created_tags.any?
  end
end
