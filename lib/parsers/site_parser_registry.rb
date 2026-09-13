require_relative 'google_maps_parser'
require_relative 'dobre_gostilne_parser'
require_relative 'facebook_parser'
require_relative 'booking_parser'

# site.domain -> класс детерминированного (без AI) парсера снапшота,
# используется синхронно в post '/api/parse' (app.rb): если для сайта
# профиля есть парсер, данные извлекаются сразу же при получении HTML от
# расширения, без ожидания отдельного rake-таска с AI. Успешный разбор тут
# считается ОКОНЧАТЕЛЬНЫМ — snap_shot помечается parsed: true и
# html_content затирается (см. app.rb).
#
# TripAdvisor сюда намеренно не входит, хотя парсер под него есть
# (см. RatingCheckRegistry) — там полный разбор (markers, адрес, часы
# работы) идёт отдельными rake-тасками по схеме заведения
# (rake snap_shots:parse_tripadvisor_restaurants/_hotels, см.
# tasks/parse_profiles.rake), и они выбирают снапшоты по parsed: [false,
# nil] + читают html_content — если пометить снапшот здесь как parsed и
# затереть html, тяжёлый разбор эти снапшоты больше никогда не увидит.
module SiteParserRegistry
  PARSERS = {
    'google.com' => GoogleMapsParser,
    'dobregostilne.si' => DobreGostilneParser,
    'facebook.com' => FacebookParser,
    'booking.com' => BookingParser
  }.freeze

  def self.for(site_domain)
    klass = PARSERS[site_domain]
    klass && klass.new
  end
end
