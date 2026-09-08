require 'csv'

namespace :import do
  desc "Импорт csv/trieste_restaurants_all.csv как Profile (tripadvisor.com) + Entity (FoodEstablishment) (rake import:trieste_restaurants)"
  task :trieste_restaurants do
    site = Site.find_by!(domain: 'tripadvisor.com')
    schema = Schema.find_by!(name: 'FoodEstablishment')

    country_tag = Tag.find_by!(name: 'Italy')
    locality_tag = Tag.find_by!(name: 'Trieste')
    food_group = Tag.find_by!(name: 'Organization:FoodEstablishment')
    features_group = Tag.find_by!(name: 'restaurant_features')
    base_type_tag = food_group.children.find_by!(name: 'FoodEstablishment')
    base_tags = [country_tag, locality_tag, base_type_tag]

    # CSV-значение establishment_type -> имя тега в группе Organization:FoodEstablishment.
    # Только 7 уникальных токенов встречаются в файле (проверено заранее) — сопоставлены
    # вручную по смыслу. То, чему нет соответствия ни здесь, ни в restaurant_features,
    # получает новый тег "_ta_<токен>" в restaurant_features (см. resolve_type_tag).
    TYPE_TAG_NAMES = {
      'Restaurants' => 'Restaurant',
      'Bars and Pubs' => 'BarOrPub',
      'Coffee and Tea' => 'CafeOrCoffeeShop',
      'Bakeries' => 'Bakery',
      'Dessert' => 'IceCreamShop',
      'Quick Bites' => 'FastFoodRestaurant'
    }.freeze

    created_tags = []

    resolve_type_tag = lambda do |token|
      mapped_name = TYPE_TAG_NAMES[token]
      tag = food_group.children.find_by(name: mapped_name) if mapped_name
      tag ||= features_group.children.find_by(name: token)
      tag ||= features_group.children.find_by(name: "_ta_#{token}")
      if tag.nil?
        tag = features_group.children.create!(name: "_ta_#{token}", active: true)
        created_tags << tag.name
      end
      tag
    end

    file = File.expand_path('../csv/trieste_restaurants_all.csv', __dir__)

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

      types = row['establishment_type'].to_s.split(',').map(&:strip).reject(&:blank?)
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
        notes: row['establishment_type']
      )

      created += 1
      puts "  + #{name} (entity ##{entity.id})"
    end

    puts "Готово: создано #{created}, пропущено (уже есть Profile с этим url) #{skipped_existing}"
    puts "Новые теги в restaurant_features: #{created_tags.uniq.join(', ')}" if created_tags.any?
  end
end
