require 'json'

# csv/{town}-booking.com.json — плоский список объектов Booking.com
# (одна запись на объект размещения), см. обсуждение формата в задаче.
module BookingComImport
  DISTANCE_RE = /\A(.+?)\s+from\s+(centre|beach)\z/.freeze
  URL_RE = %r{/hotel/[a-z]{2}/(.+?)\.[a-z-]+\.html\z}.freeze

  # 'city' в JSON иногда с диакритикой (Portorož), тег локальности в базе
  # (создан при импорте с TripAdvisor, из URL-слага) — без неё (Portoroz).
  CITY_ALIASES = { 'Portorož' => 'Portoroz' }.freeze

  def self.slug(url)
    m = url.match(URL_RE)
    m && m[1]
  end

  def self.locality_name(city)
    CITY_ALIASES.fetch(city, city)
  end

  # tags — либо "<расстояние> from centre/beach" (идёт в details как
  # ключ "from centre"/"from beach"), либо произвольная метка (Beach
  # nearby, Beachfront) — идёт в details['tags'] списком.
  def self.build_details(row)
    details = {
      'city' => row['city'],
      'private_host' => row['private_host']
    }
    details['rating_label'] = row['rating_label'] if row['rating_label'].present?
    details['text'] = row['text'] if row['text'].present?

    slug_value = slug(row['review_url'])
    details['booking_slug'] = slug_value if slug_value

    plain_tags = []
    Array(row['tags']).each do |tag|
      m = tag.match(DISTANCE_RE)
      if m
        details["from #{m[2]}"] = m[1]
      else
        plain_tags << tag
      end
    end
    details['tags'] = plain_tags if plain_tags.any?

    details
  end
end

namespace :import do
  desc "Импорт Booking.com JSON из csv/*-booking.json и csv/*-booking.com.json как Profile; там, где однозначно, связывает с уже существующим Entity того же города (rake import:diversorio_booking)"
  task :diversorio_booking do
    site = Site.find_by!(domain: 'booking.com')
    lodging_schema = Schema.find_by!(name: 'LodgingBusiness')

    created = 0
    skipped_existing = 0
    linked = 0
    not_linked = 0

    # Разные выгрузки называли файлы по-разному: "{town}-booking.com.json"
    # (triestia.com, cms-diversorio) и "{town}-booking.json" (istriada.com) —
    # формат содержимого одинаковый, ловим оба варианта, но не более широкий
    # "*booking*.json", чтобы случайно не подхватить что-то постороннее.
    files = (
      Dir.glob(File.expand_path('../csv/*-booking.json', __dir__)) +
      Dir.glob(File.expand_path('../csv/*-booking.com.json', __dir__))
    ).uniq.sort
    files.each do |file|
      puts "=== #{File.basename(file)} ==="
      rows = JSON.parse(File.read(file))

      rows.each do |row|
        url = row['review_url']&.strip
        next if url.blank?

        if Profile.exists?(site: site, url: url)
          skipped_existing += 1
          next
        end

        city_tag = Tag.find_by(name: BookingComImport.locality_name(row['city']))
        profileable = nil

        if city_tag
          candidates = Entity.where(schema_id: lodging_schema.id)
                              .joins(:taggings)
                              .where(taggings: { tag_id: city_tag.id })
                              .where('LOWER(entities.name) = ?', row['name'].to_s.strip.downcase)
                              .distinct
                              .to_a

          if candidates.size == 1
            profileable = candidates.first
            linked += 1
          else
            not_linked += 1
          end
        else
          not_linked += 1
        end

        Profile.create!(
          site: site,
          url: url,
          profileable: profileable,
          title: row['name'],
          rating: row['rating'],
          review_count: row['review_count'],
          details: BookingComImport.build_details(row)
        )

        created += 1
      end
    end

    puts "Готово: создано #{created}, пропущено (уже есть) #{skipped_existing}"
    puts "связано с Entity: #{linked}, без связи: #{not_linked}"
  end
end
