require 'nokogiri'
require 'json'

# Извлекает rating/review_count/price_level из HTML-снапшота страницы
# заведения на dobregostilne.si (site.domain == 'dobregostilne.si') без AI.
#
# Публичный метод повторяет сигнатуру DeepseekClient#extract_profile_data
# (см. lib/parsers/tripadvisor_restaurant_parser.rb) — этот класс можно
# передать как client: в SnapShotParser.new, вся остальная логика (merge в
# profile.details, синхронизация profile.rating/review_count,
# parsed/parsed_at) отработает без изменений.
#
# Источник в приоритете — JSON-LD (<script type="application/ld+json"> с
# aggregateRating), как у TripAdvisor: это устойчивее к смене CSS-классов
# при редизайне сайта. Если JSON-LD нет или в нём нет нужных полей —
# фоллбек на видимый текст страницы (regex).
#
# Сверено на реальном снапшоте (SnapShot#1175, gostilnica-gust): JSON-LD
# отдаёт rating (ratingValue) и price_level (priceRange на верхнем уровне
# объекта, не внутри aggregateRating) верно, но количество отзывов там
# лежит под ключом ratingCount, а не reviewCount (schema.org допускает оба —
# у этого сайта reviewCount вообще нет ни на одной странице).
class DobreGostilneParser
  REVIEW_COUNT_RE = /(\d{1,3}(?:[,.\s]\d{3})*)\s*(?:ocen[ae]?|mnenj|review)/i
  PRICE_LEVEL_RE = /€{1,4}/

  def extract_profile_data(html, instructions: nil)
    doc = Nokogiri::HTML(html.to_s)
    biz = business_ld_json(doc)

    details = {}

    rating = biz&.dig('aggregateRating', 'ratingValue')
    details['rating'] = rating.to_s if rating

    review_count = biz&.dig('aggregateRating', 'reviewCount') || biz&.dig('aggregateRating', 'ratingCount')
    details['review_count'] = review_count.to_s if review_count

    price_level = biz&.dig('priceRange') || find_price_level(doc.text)
    details['price_level'] = price_level if price_level

    details['rating'] ||= find_rating_fallback(doc.text)
    details['review_count'] ||= find_review_count_fallback(doc.text)

    { 'markers' => {}, 'details' => details }
  end

  private

  def business_ld_json(doc)
    doc.css('script[type="application/ld+json"]').each do |script|
      data = begin
        JSON.parse(script.text)
      rescue JSON::ParserError
        next
      end
      return data if data.is_a?(Hash) && data['aggregateRating']
    end
    nil
  end

  def find_price_level(text)
    text[PRICE_LEVEL_RE]
  end

  def find_rating_fallback(text)
    token = text.strip.split(/\s+/).first(80).find { |t| t =~ /\A[0-5][.,]\d\z/ }
    token&.tr(',', '.')
  end

  def find_review_count_fallback(text)
    match = text[REVIEW_COUNT_RE, 1]
    match&.strip
  end
end
