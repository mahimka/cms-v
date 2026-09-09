require 'nokogiri'
require 'json'

# Извлекает markers/details из HTML страницы ресторана на TripAdvisor без
# AI. Публичный метод намеренно повторяет сигнатуру
# DeepseekClient#extract_profile_data(html, instructions:) — экземпляр этого
# класса можно передать как client: в SnapShotParser.new, и вся остальная
# логика (создание Marker/ProfileMarker, merge в profile.details,
# rating/review_count, sync title/h1/scraped_at, parsed/parsed_at)
# отработает без изменений, как и для AI-клиента.
#
# Источники данных, по надёжности (проверено на 962 реальных снапшотах
# ресторанов Триеста):
# 1. JSON-LD (<script type="application/ld+json"> с @type FoodEstablishment) —
#    address/geo/servesCuisine/openingHours почти всегда (99.9%), rating —
#    когда у заведения достаточно отзывов, чтобы TripAdvisor его посчитал
#    (80.6%).
# 2. Панель "About" на странице — блок из пар <div>ЛЕЙБЛ</div><div>значение</div>
#    (CUISINES/Meal types/PRICE/FEATURES/Special Diets). CSS-классы там —
#    хеши webpack-сборки TripAdvisor и могут смениться при редизайне, поэтому
#    сопоставление идёт по ТЕКСТУ лейбла, а не по классу.
#
# 3. Строка ранжирования рядом с рейтингом ("#1 of 52 Coffee & Tea Spots in
#    Trieste Dessert, Italian, $$ - $$$") — единственный надёжный источник
#    markers.establishment_type (80.7% страниц): исходный тип из CSV при
#    листинге мог не заметить категорию, а тут она напрямую от TripAdvisor.
#    Кухни/цена оттуда же идут доп. фоллбеком к JSON-LD/About-панели.
#
# Не реализовано (нет надёжного паттерна на реальных страницах): markers
# great_for, dishes.
class TripadvisorRestaurantParser
  ABOUT_LABELS = {
    'cuisines' => :cuisines,
    'meal types' => :meal_types,
    'price' => :price,
    'features' => :features,
    'special diets' => :special_diets
  }.freeze

  DAY_KEYS = {
    'Monday' => 'hours_monday',
    'Tuesday' => 'hours_tuesday',
    'Wednesday' => 'hours_wednesday',
    'Thursday' => 'hours_thursday',
    'Friday' => 'hours_friday',
    'Saturday' => 'hours_saturday',
    'Sunday' => 'hours_sunday'
  }.freeze

  COUNTRY_NAMES = { 'IT' => 'Italy' }.freeze

  def extract_profile_data(html, instructions: nil)
    doc = Nokogiri::HTML(html.to_s)
    biz = business_ld_json(doc)
    about = about_panel(doc)
    ranking = ranking_line(doc)

    {
      'markers' => extract_markers(doc, biz, about, ranking),
      'details' => extract_details(doc, biz, about)
    }
  end

  private

  # Среди всех ld+json блоков ищем тот, что описывает само заведение (у
  # TripAdvisor на странице ресторана их обычно 3: Organization, BreadcrumbList
  # и сам FoodEstablishment — этот единственный содержит address).
  def business_ld_json(doc)
    doc.css('script[type="application/ld+json"]').each do |script|
      data = begin
        JSON.parse(script.text)
      rescue JSON::ParserError
        next
      end
      return data if data.is_a?(Hash) && data['address']
    end
    nil
  end

  # Лейбл -> сосед-значение, одним проходом по всем div на странице.
  # "Лейбл" = div без вложенных тегов, чей текст совпадает с одним из
  # ABOUT_LABELS (без учёта регистра) — не зависит от CSS-классов.
  def about_panel(doc)
    result = {}
    doc.css('div').each do |node|
      next unless node.elements.empty?

      key = ABOUT_LABELS[node.text.strip.downcase]
      next unless key

      result[key] = node.next_element
    end
    result
  end

  # Значение рядом с лейблом — либо список "чипов" (FEATURES: каждая опция
  # в своём <span>), либо просто текст через запятую (CUISINES, PRICE и т.п.).
  def chip_values(el)
    return [] unless el

    spans = el.css('span')
    texts = spans.any? ? spans.map { |s| s.text.strip } : el.text.to_s.split(',').map(&:strip)
    texts.reject(&:empty?)
  end

  def extract_markers(doc, biz, about, ranking)
    markers = {}

    markers['establishment_type'] = [ranking[:category]] if ranking[:category]

    cuisines = Array(biz && biz['servesCuisine'])
    cuisines = chip_values(about[:cuisines]) if cuisines.empty?
    cuisines = (cuisines + ranking[:cuisines]).uniq
    markers['cuisines'] = cuisines unless cuisines.empty?

    meal_types = chip_values(about[:meal_types])
    markers['meal_types'] = meal_types unless meal_types.empty?

    dietary = chip_values(about[:special_diets])
    markers['dietary_restrictions'] = dietary unless dietary.empty?

    features = chip_values(about[:features])
    features << 'Reservations' if biz && biz['acceptsReservations'] == true && !features.include?('Reservations')
    markers['features'] = features unless features.empty?

    price_category = categorize_price(price_symbols(biz, about, ranking))
    markers['price_range'] = [price_category] if price_category

    markers['michelin_guide'] = ['MICHELIN Guide'] if doc.text.include?('MICHELIN Guide')

    markers
  end

  def price_symbols(biz, about, ranking)
    (about[:price] && about[:price].text.strip) || (biz && biz['priceRange']) || ranking[:price_symbol]
  end

  DOLLAR_RANGE = /\A\$+(\s*[-–]\s*\$+)?\z/

  # "#1 of 52 Coffee & Tea Spots in Trieste" — родительский <span> этой
  # ссылки идёт первым в строке ранжирования, следующий соседний <span>
  # содержит кухни/цену той же строки ("Dessert, Italian, $$ - $$$"),
  # каждая как отдельная <a><span>. Категория из этой строки — тип заведения
  # от самого TripAdvisor, точнее, чем то, что могло быть замечено при
  # первичном скрейпе листинга.
  RANKING_RE = /\A#\d+\s+of\s+\d+\s+(.+?)\s+in\s+/

  CATEGORY_NORMALIZE = {
    'Restaurant' => 'Restaurants',
    'Dessert Spot' => 'Dessert',
    'Dessert Spots' => 'Dessert',
    'Coffee & Tea Spot' => 'Coffee & Tea',
    'Coffee & Tea Spots' => 'Coffee & Tea',
    'Specialty Food Markets' => 'Specialty Food Market'
  }.freeze

  def ranking_line(doc)
    link = doc.css('a').find { |el| el.text =~ RANKING_RE }
    return { category: nil, cuisines: [], price_symbol: nil } unless link

    raw_category = link.text.strip.match(RANKING_RE)[1]
    category = CATEGORY_NORMALIZE.fetch(raw_category, raw_category)

    extra = link.parent.next_element&.css('a span')&.map { |s| s.text.strip }&.reject(&:empty?) || []
    price_symbol, cuisines = extra.partition { |t| t.match?(DOLLAR_RANGE) }

    { category: category, cuisines: cuisines, price_symbol: price_symbol.first }
  end

  def categorize_price(symbols)
    return nil unless symbols && symbols.match?(DOLLAR_RANGE)

    runs = symbols.scan(/\$+/)
    case runs.map(&:length).max
    when 1 then 'Cheap Eats'
    when 2, 3 then 'Mid-range'
    else 'Fine Dining'
    end
  end

  def extract_details(doc, biz, about)
    details = {}
    return details unless biz

    address = format_address(biz['address'])
    details['address'] = address if address

    rating = biz.dig('aggregateRating', 'ratingValue')
    details['rating'] = rating.to_s unless rating.nil?

    review_count = biz.dig('aggregateRating', 'reviewCount')
    details['review_count'] = review_count.to_s unless review_count.nil?

    details['phone'] = biz['telephone'] if biz['telephone']

    latitude = biz.dig('geo', 'latitude')
    details['latitude'] = latitude.to_s unless latitude.nil?

    longitude = biz.dig('geo', 'longitude')
    details['longitude'] = longitude.to_s unless longitude.nil?

    # href часто пуст — TripAdvisor резолвит реальный внешний URL через JS
    # (клик), не отдавая его в статичной разметке.
    website = doc.at_css('a[data-automation="restaurantsWebsiteButton"]')&.[]('href')
    details['website'] = website if website && !website.empty?

    # PRICE-строка, которая НЕ похожа на $-категорию (например, "€10-20") —
    # то, что markers.price_range/categorize_price сознательно не трогает.
    price_text = about[:price] && about[:price].text.strip
    details['price_range_text'] = price_text if price_text && !price_text.match?(DOLLAR_RANGE)

    details.merge!(hours_by_day(biz['openingHoursSpecification']))

    details
  end

  def format_address(addr)
    return nil unless addr

    country = addr.dig('addressCountry', 'name')
    country = COUNTRY_NAMES.fetch(country, country) if country

    parts = [
      addr['streetAddress'],
      addr['addressLocality'],
      [addr['postalCode'], addr['addressRegion']].compact.reject(&:empty?).join(' '),
      country
    ]

    full = parts.compact.reject(&:empty?).join(', ')
    full.empty? ? nil : full
  end

  # openingHoursSpecification может содержать несколько интервалов на один
  # день (например, обед и ужин отдельно) — группируем и склеиваем через ", ".
  # Дни, для которых записей вообще нет, в результат не попадают (per
  # промпту: нет данных — не пишем ключ).
  def hours_by_day(specs)
    return {} unless specs

    specs.group_by { |s| s['dayOfWeek'] }.each_with_object({}) do |(day, entries), h|
      key = DAY_KEYS[day]
      next unless key

      h[key] = entries.map { |e| "#{fmt_time(e['opens'])}-#{fmt_time(e['closes'])}" }.join(', ')
    end
  end

  def fmt_time(t)
    t.to_s.sub(/:00\z/, '')
  end
end
