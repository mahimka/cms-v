require 'nokogiri'
require 'json'
require_relative 'tripadvisor_shared'

# Извлекает markers/details из HTML страницы отеля на TripAdvisor без AI —
# аналог TripadvisorRestaurantParser (тот же extract_profile_data(html,
# instructions:), тот же client: для SnapShotParser). Общие с ним куски —
# в tripadvisor_shared.rb.
#
# Источники данных, по надёжности (проверено на 542 реальных снапшотах
# отелей Триеста):
# 1. JSON-LD (<script type="application/ld+json"> с @type LodgingBusiness) —
#    address (99.9%), geo (99.3%). rating/review_count/amenityFeatures —
#    только когда у отеля достаточно отзывов, чтобы TripAdvisor их посчитал
#    (~57-76%). telephone и sameAs (внешний сайт отеля) — очень редко в
#    JSON-LD (~3%), в отличие от ресторанов — тут это основной источник для
#    website, лучшего варианта нет (кнопка "Visit hotel website" на
#    странице всегда с пустым href, а mailto-ссылок у отелей просто нет).
# 2. Строка ранжирования рядом с рейтингом ("#4 of 54 hotels in Trieste") —
#    markers.establishment_type, тот же приём и с той же точностью (75.6%),
#    что и у ресторанов, только тут словарь — Hotels/B&Bs & Inns/Specialty
#    lodgings (без дополнительных кухни/цены в той же строке — у отелей их
#    там просто нет).
# 3. Секция "Good to know" (якорь — data-test-target=
#    "hr-about-group-good-to-know", это стабильный атрибут, не хеш) — блоки
#    вида [лейбл][значение, может быть несколько]. Даёт HOTEL CLASS
#    (звёзды, ~44%), HOTEL STYLE (Romantic/Luxury/Budget/... , ~58%),
#    Languages Spoken (~40%). LICENSE NUMBER из той же секции не берём — в
#    разметке склеен с текстом кнопки "Read more", отдельно не выделяется.
# 4. data-test-target="amenity_text" — список аменити по одному на <li>,
#    фоллбек к JSON-LD amenityFeatures (добавляет ещё ~1% сверху).
# 5. "Review Summary" (см. tripadvisor_shared.rb) — Location/Cleanliness/
#    Rooms/Service/Amenities/Value/Atmosphere, ~1% страниц.
#
# Не реализовано: markers.dishes/great_for-эквивалентов для отелей на
# реальных страницах не нашлось; room_types/hotel-links секции в сохранённом
# HTML всегда пустые (контент подгружается по клику, до захвата не доходит).
class TripadvisorHotelParser
  include TripadvisorPageHelpers

  RANKING_RE = /\A#\d+\s+of\s+\d+\s+(.+?)\s+in\s+/

  CATEGORY_NORMALIZE = {
    'B&Bs / Inns' => 'B&Bs & Inns',
    'Specialty lodging' => 'Specialty lodgings',
    'hotels' => 'Hotels'
  }.freeze

  LANGUAGES_SUFFIX = /\s+and\s+\d+\s+more\z/.freeze

  def extract_profile_data(html, instructions: nil)
    doc = Nokogiri::HTML(html.to_s)
    biz = business_ld_json(doc)
    good_to_know = good_to_know_blocks(doc)

    {
      'markers' => extract_markers(doc, biz, good_to_know),
      'details' => extract_details(doc, biz, good_to_know)
    }
  end

  private

  # "Good to know": заголовок с data-test-target идёт отдельным листовым
  # div, а сами блоки — в его соседе. Внутри каждого блока первый дочерний
  # элемент — лейбл, остальные — одно или несколько значений (например,
  # HOTEL STYLE обычно приходит как 2+ отдельных value-div, каждый со своим
  # словом, а не одной строкой через запятую).
  def good_to_know_blocks(doc)
    header = doc.at_css("[data-test-target='hr-about-group-good-to-know']")
    container = header&.next_element
    return {} unless container

    container.elements.each_with_object({}) do |block, result|
      els = block.elements
      next if els.empty?

      label = els[0].text.strip
      values = els[1..].map { |e| e.text.strip }.reject(&:empty?)
      next if values.empty?

      if label.start_with?('HOTEL CLASS')
        result[:hotel_class] = values.first
      elsif label == 'HOTEL STYLE'
        result[:hotel_style] = values
      elsif label == 'Languages Spoken'
        result[:languages_spoken] = values.flat_map { |v| v.sub(LANGUAGES_SUFFIX, '').split(',').map(&:strip) }
      end
    end
  end

  def extract_markers(doc, biz, good_to_know)
    markers = {}

    category = ranking_category(doc)
    markers['establishment_type'] = [category] if category

    features = amenity_features(doc, biz)
    markers['features'] = features unless features.empty?

    markers['hotel_style'] = good_to_know[:hotel_style] if good_to_know[:hotel_style]
    markers['languages_spoken'] = good_to_know[:languages_spoken] if good_to_know[:languages_spoken]

    price_category = categorize_price(biz && biz['priceRange'])
    markers['price_range'] = [price_category] if price_category

    review_summary = review_summary_markers(doc)
    markers['review_summary'] = review_summary unless review_summary.empty?

    markers
  end

  def ranking_category(doc)
    link = doc.css('a').find { |el| el.text =~ RANKING_RE }
    return nil unless link

    raw_category = link.text.strip.match(RANKING_RE)[1]
    CATEGORY_NORMALIZE.fetch(raw_category, raw_category)
  end

  def amenity_features(doc, biz)
    json_names = Array(biz && biz['amenityFeatures']).select { |a| a['value'] == true }.map { |a| a['name'] }
    dom_names = doc.css('[data-test-target="amenity_text"]').map { |el| el.text.strip }.reject(&:empty?)
    (json_names + dom_names).uniq
  end

  def categorize_price(price_range_text)
    case dollar_tier(price_range_text)
    when 1 then 'Budget'
    when 2, 3 then 'Mid-range'
    when 4 then 'Luxury'
    end
  end

  def extract_details(doc, biz, good_to_know)
    details = {}
    return details unless biz

    address = format_address(biz['address'])
    details['address'] = address if address

    rating = biz.dig('aggregateRating', 'ratingValue')
    details['rating'] = rating.to_s unless rating.nil?

    review_count = biz.dig('aggregateRating', 'reviewCount')
    details['review_count'] = review_count.to_s unless review_count.nil?

    phone = biz['telephone'] || doc.at_css('a[href^="tel:"]')&.[]('href')&.sub(/\Atel:/, '')
    details['phone'] = phone if phone

    latitude = biz.dig('geo', 'latitude')
    details['latitude'] = latitude.to_s unless latitude.nil?

    longitude = biz.dig('geo', 'longitude')
    details['longitude'] = longitude.to_s unless longitude.nil?

    details['website'] = biz['sameAs'] if biz['sameAs']

    star_rating = good_to_know[:hotel_class]&.match(/\d+/)&.to_s
    details['star_rating'] = star_rating if star_rating

    details
  end
end
