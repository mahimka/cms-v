require 'csv'

namespace :import do
  desc "Импорт ресторанов из project/*_restaurants.csv как Entity + Profile (tripadvisor) (rake import:tripadvisor_restaurants)"
  task :tripadvisor_restaurants do
    schema = Schema.find_by!(name: 'FoodEstablishment')
    site = Site.find_by!(domain: 'tripadvisor.com')
    common_tags = Tag.where(name: ['Coastal–Karst', 'Slovenia', 'FoodEstablishment', 'Restaurant']).to_a

    raise "Ожидались 4 общих тега, найдено #{common_tags.size}: #{common_tags.map(&:name)}" if common_tags.size != 4

    files = Dir.glob(File.expand_path('../project/*_restaurants.csv', __dir__)).sort

    created = 0
    skipped_existing = 0
    skipped_no_locality_tag = 0

    files.each do |file|
      puts "=== #{File.basename(file)} ==="

      CSV.foreach(file, headers: true, liberal_parsing: true) do |row|
        name = row[0]&.strip
        url = row[1]&.strip
        locality_name = row[2]&.strip

        next if name.blank? || url.blank?

        if Profile.exists?(site: site, url: url)
          skipped_existing += 1
          next
        end

        locality_tag = Tag.find_by(name: locality_name)
        unless locality_tag
          puts "  ! пропуск (нет тега addressLocality для #{locality_name.inspect}): #{name}"
          skipped_no_locality_tag += 1
          next
        end

        entity = Entity.create!(name: name, schema: schema, active: true)

        (common_tags + [locality_tag]).each do |tag|
          entity.taggings.where(tag_id: tag.id).first_or_create
        end

        Profile.create!(site: site, url: url, profileable: entity)

        created += 1
        puts "  + #{name} (entity ##{entity.id})"
      end
    end

    puts "Готово: создано #{created}, пропущено (уже есть Profile с этим url) #{skipped_existing}, пропущено (нет тега города) #{skipped_no_locality_tag}"
  end
end
