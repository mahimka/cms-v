require_relative 'tripadvisor_rating_parser'

# site.domain -> лёгкий парсер, вытягивающий ТОЛЬКО rating/review_count —
# для сайтов, у которых уже есть отдельный, более тяжёлый offline-разбор
# (markers, адрес и т.п. — TripAdvisor, см. tasks/parse_profiles.rake), и
# который нельзя случайно "занять" синхронным разбором в post '/api/parse'.
#
# В отличие от SiteParserRegistry: не создаёт свой SnapShot, не трогает
# snap_shot.parsed/html_content и не идёт через SnapShotParser — просто
# накатывает rating/review_count в profile.details/rating/review_count
# поверх того, что уже там есть, и ничего больше. Безопасно вызывать при
# каждом заходе расширения на страницу, сколько угодно часто — используется
# для регулярной сверки рейтинга без полного пересбора профиля.
module RatingCheckRegistry
  PARSERS = {
    'tripadvisor.com' => TripadvisorRatingParser
  }.freeze

  def self.for(site_domain)
    klass = PARSERS[site_domain]
    klass && klass.new
  end

  def self.apply(profile, html)
    parser = self.for(profile.site&.domain)
    return nil unless parser

    details = parser.extract_profile_data(html)['details']
    return nil if details.blank?

    profile.details = (profile.details || {}).merge(details)

    rating = SnapShotParser.parse_rating(details['rating'])
    profile.rating = rating if rating

    review_count = SnapShotParser.parse_review_count(details['review_count'])
    profile.review_count = review_count if review_count

    profile.save!
    details
  end
end
