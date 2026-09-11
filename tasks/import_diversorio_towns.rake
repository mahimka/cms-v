require 'csv'

# csv/*_restaurants_all.csv и csv/*_hotels_all.csv собраны скрейпингом
# "рядом с городом X" на TripAdvisor — из-за этого часть строк на самом
# деле про другие города (вплоть до Триеста, Италия, у соседних городов
# набралось мало своих заведений и TripAdvisor подмешал более широкий
# радиус). Имени файла доверять нельзя — город и (иногда) само название
# берём из URL, а не из CSV.
module DiversorioTownsImport
  # ".../Reviews-Hotel_Convent_Adria-Ankaran_Slovenian_Littoral_Region.html"
  # -> ["Hotel Convent Adria", "Ankaran"]. Проверено на всех 1469 строках
  # исходных csv — 0 непроизвольных совпадений.
  URL_RE = /Reviews-(.+)-([A-Za-z][A-Za-z_]*)\.html\z/.freeze

  def self.parse_url(url)
    m = url.match(URL_RE)
    return [nil, nil] unless m

    [m[1].tr('_', ' '), m[2].split('_').first]
  end

  # Часть name в CSV у отелей побита — вместо названия туда попал
  # доступный текст рейтингового виджета ("05 of 5 bubbles(5)",
  # "33.3 of 5 bubbles(75)"). У 56% строк в *_hotels_all.csv. У ресторанов
  # такого не встретилось, но проверяем везде на всякий случай.
  def self.broken_name?(name)
    name.to_s.match?(/of 5 bubbles/i)
  end

  def self.resolve_name(csv_name, url_name)
    csv_name.present? && !broken_name?(csv_name) ? csv_name : url_name
  end
end

namespace :import do
  desc "Импорт ресторанов из csv/*_restaurants_all.csv, город берётся из URL (rake import:diversorio_restaurants)"
  task :diversorio_restaurants do
    site = Site.find_by!(domain: 'tripadvisor.com')
    schema = Schema.find_by!(name: 'FoodEstablishment')
    country_tag = Tag.find_by!(name: 'Slovenia')
    locality_group = Tag.find_by!(name: 'addressLocality')
    food_group = Tag.find_by!(name: 'Organization:FoodEstablishment')
    features_group = Tag.find_by!(name: 'restaurant_features')
    base_type_tag = food_group.children.find_by!(name: 'FoodEstablishment')

    type_tag_names = {
      'Restaurants' => 'Restaurant',
      'Bars and Pubs' => 'BarOrPub',
      'Coffee and Tea' => 'CafeOrCoffeeShop',
      'Bakeries' => 'Bakery',
      'Dessert' => 'IceCreamShop',
      'Quick Bites' => 'FastFoodRestaurant'
    }

    new_locality_tags = []
    new_type_tags = []

    resolve_locality = lambda do |city|
      tag = Tag.find_by(name: city)
      if tag.nil?
        tag = locality_group.children.create!(name: city, active: true)
        new_locality_tags << city
      end
      tag
    end

    resolve_type_tag = lambda do |token|
      mapped_name = type_tag_names[token]
      tag = food_group.children.find_by(name: mapped_name) if mapped_name
      tag ||= features_group.children.find_by(name: token)
      tag ||= features_group.children.find_by(name: "_ta_#{token}")
      if tag.nil?
        tag = features_group.children.create!(name: "_ta_#{token}", active: true)
        new_type_tags << tag.name
      end
      tag
    end

    files = Dir.glob(File.expand_path('../csv/*_restaurants_all.csv', __dir__)).sort
    created = 0
    skipped_existing = 0
    skipped_bad_url = 0

    files.each do |file|
      puts "=== #{File.basename(file)} ==="

      CSV.foreach(file, headers: true, liberal_parsing: true) do |row|
        url = row['url']&.strip
        next if url.blank?

        url_name, city = DiversorioTownsImport.parse_url(url)
        name = DiversorioTownsImport.resolve_name(row['name']&.strip, url_name)
        if name.blank? || city.blank?
          skipped_bad_url += 1
          next
        end

        if Profile.exists?(site: site, url: url)
          skipped_existing += 1
          next
        end

        locality_tag = resolve_locality.call(city)

        types = row['establishment_types'].to_s.split(',').map(&:strip).reject(&:blank?)
        type_tags = types.map { |token| resolve_type_tag.call(token) }

        entity = Entity.create!(name: name, schema: schema, active: true)
        ([country_tag, locality_tag, base_type_tag] + type_tags).uniq.each do |tag|
          entity.taggings.where(tag_id: tag.id).first_or_create!
        end

        Profile.create!(
          site: site,
          url: url,
          profileable: entity,
          title: name,
          rating: row['rating'].presence&.to_f,
          review_count: row['reviews_count'].presence&.to_i,
          notes: row['establishment_types']
        )

        created += 1
      end
    end

    puts "Готово: создано #{created}, пропущено (уже есть) #{skipped_existing}, пропущено (не распарсили url) #{skipped_bad_url}"
    puts "Новые теги городов: #{new_locality_tags.uniq.join(', ')}" if new_locality_tags.any?
    puts "Новые теги типов: #{new_type_tags.uniq.join(', ')}" if new_type_tags.any?
  end

  desc "Импорт отелей из csv/*_hotels_all.csv, город из URL, Триест пропускается (rake import:diversorio_hotels)"
  task :diversorio_hotels do
    site = Site.find_by!(domain: 'tripadvisor.com')
    schema = Schema.find_by!(name: 'LodgingBusiness')
    country_tag = Tag.find_by!(name: 'Slovenia')
    locality_group = Tag.find_by!(name: 'addressLocality')
    lodging_group = Tag.find_by!(name: 'Organization:LodgingBusiness')
    base_type_tag = lodging_group.children.find_by!(name: 'LodgingBusiness')

    type_tag_names = {
      'Hotels' => 'Hotel',
      'B&Bs & Inns' => 'BedAndBreakfast',
      'Hostels' => 'Hostel',
      'Campgrounds' => 'Campground',
      'Pensions' => 'BedAndBreakfast',
      'Condos' => 'VacationRental',
      'Cottage' => 'VacationRental',
      'Villa' => 'VacationRental'
    }

    new_locality_tags = []
    new_type_tags = []
    skipped_trieste = 0

    resolve_locality = lambda do |city|
      tag = Tag.find_by(name: city)
      if tag.nil?
        tag = locality_group.children.create!(name: city, active: true)
        new_locality_tags << city
      end
      tag
    end

    resolve_type_tag = lambda do |token|
      mapped_name = type_tag_names[token]
      tag = lodging_group.children.find_by(name: mapped_name) if mapped_name
      tag ||= lodging_group.children.find_by(name: token)
      tag ||= lodging_group.children.find_by(name: "_ta_#{token}")
      if tag.nil?
        tag = lodging_group.children.create!(name: "_ta_#{token}", active: true)
        new_type_tags << tag.name
      end
      tag
    end

    files = Dir.glob(File.expand_path('../csv/*_hotels_all.csv', __dir__)).sort
    created = 0
    skipped_existing = 0
    skipped_bad_url = 0

    files.each do |file|
      puts "=== #{File.basename(file)} ==="

      CSV.foreach(file, headers: true, liberal_parsing: true) do |row|
        url = row['url']&.strip
        next if url.blank?

        url_name, city = DiversorioTownsImport.parse_url(url)
        name = DiversorioTownsImport.resolve_name(row['name']&.strip, url_name)
        if name.blank? || city.blank?
          skipped_bad_url += 1
          next
        end

        if city == 'Trieste'
          skipped_trieste += 1
          next
        end

        if Profile.exists?(site: site, url: url)
          skipped_existing += 1
          next
        end

        locality_tag = resolve_locality.call(city)

        types = row['property_types'].to_s.split(',').map(&:strip).reject(&:blank?)
        type_tags = types.map { |token| resolve_type_tag.call(token) }

        entity = Entity.create!(name: name, schema: schema, active: true)
        ([country_tag, locality_tag, base_type_tag] + type_tags).uniq.each do |tag|
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
      end
    end

    puts "Готово: создано #{created}, пропущено (уже есть) #{skipped_existing}, пропущено (Триест) #{skipped_trieste}, пропущено (не распарсили url) #{skipped_bad_url}"
    puts "Новые теги городов: #{new_locality_tags.uniq.join(', ')}" if new_locality_tags.any?
    puts "Новые теги типов: #{new_type_tags.uniq.join(', ')}" if new_type_tags.any?
  end
end
