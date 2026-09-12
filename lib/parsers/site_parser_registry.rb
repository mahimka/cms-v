require_relative 'google_maps_parser'
require_relative 'dobre_gostilne_parser'
require_relative 'facebook_parser'

# site.domain -> класс детерминированного (без AI) парсера снапшота,
# используется синхронно в post '/api/parse' (app.rb): если для сайта
# профиля есть парсер, данные извлекаются сразу же при получении HTML от
# расширения, без ожидания отдельного rake-таска с AI.
#
# TripAdvisor сюда намеренно не входит — там разбор идёт по схеме профиля
# (Restaurant/Hotel — разные парсеры) отдельными rake-тасками
# (rake snap_shots:parse_tripadvisor_restaurants/_hotels), см. tasks/parse_profiles.rake.
module SiteParserRegistry
  PARSERS = {
    'google.com' => GoogleMapsParser,
    'dobregostilne.si' => DobreGostilneParser,
    'facebook.com' => FacebookParser
  }.freeze

  def self.for(site_domain)
    klass = PARSERS[site_domain]
    klass && klass.new
  end
end
