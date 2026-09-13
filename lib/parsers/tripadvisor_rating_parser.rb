require 'nokogiri'
require 'json'
require_relative 'tripadvisor_shared'

# Лёгкий парсер только rating/review_count со страницы TripAdvisor — для
# регулярной проверки через post '/api/parse' (SiteParserRegistry), в
# отличие от тяжёлых TripadvisorRestaurantParser/TripadvisorHotelParser
# (markers, адрес, часы работы, кухни и т.п.), которые запускаются отдельно
# по схеме заведения (rake snap_shots:parse_tripadvisor_restaurants/_hotels,
# см. tasks/parse_profiles.rake) — не нужны при каждой периодической сверке
# рейтинга.
#
# aggregateRating в JSON-LD одинаков для FoodEstablishment и
# LodgingBusiness — этому парсеру, в отличие от тяжёлых, схема заведения не
# нужна вообще, поэтому он один на весь tripadvisor.com (см.
# SiteParserRegistry).
class TripadvisorRatingParser
  include TripadvisorPageHelpers

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
end
