require 'nokogiri'
require 'json'

# Извлекает rating/review_count из HTML-снапшота страницы отеля на
# booking.com (site.domain == 'booking.com') без AI.
#
# Публичный метод повторяет сигнатуру DeepseekClient#extract_profile_data
# (см. lib/parsers/tripadvisor_restaurant_parser.rb) — этот класс можно
# передать как client: в SnapShotParser.new, вся остальная логика (merge в
# profile.details, синхронизация profile.rating/review_count,
# parsed/parsed_at) отработает без изменений.
#
# booking.com отдаёт полноценный JSON-LD (@type Hotel) с aggregateRating —
# rating тут по шкале 0..10 (не 0..5, как у TripAdvisor/Google, и не % как
# у Facebook) — сохраняем как есть, единая колонка profile.rating общая для
# всех парсеров, единица измерения зависит от сайта.
#
# Сверено на реальном снапшоте (Apartments Zakinja Portoroz, profile #2680):
# rating=9.4, review_count=87 — совпадает с тем, что видно на самой странице.
class BookingParser
  def extract_profile_data(html, instructions: nil)
    doc = Nokogiri::HTML(html.to_s)
    biz = business_ld_json(doc)

    details = {}

    if biz
      rating = biz.dig('aggregateRating', 'ratingValue')
      details['rating'] = rating.to_s unless rating.nil?

      review_count = biz.dig('aggregateRating', 'reviewCount')
      details['review_count'] = review_count.to_s unless review_count.nil?
    end

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
end
