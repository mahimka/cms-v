require 'nokogiri'
require 'json'

# Извлекает markers/details из HTML-снапшота страницы watersport-center на
# vdws.de (site.domain == 'vdws.de') без AI.
#
# Публичный метод повторяет сигнатуру DeepseekClient#extract_profile_data
# (см. lib/parsers/tripadvisor_restaurant_parser.rb) — этот класс можно
# передать как client: в SnapShotParser.new, вся остальная логика (merge в
# profile.details, создание Marker/ProfileMarker, parsed/parsed_at)
# отработает без изменений.
#
# Источники, по надёжности (проверено на 11 реальных страницах):
# 1. JSON-LD (<script type="application/ld+json"> @type LocalBusiness) —
#    телефон/email/адрес/geo/openingHours, почти всегда есть (10 из 11);
#    addressCountry там ISO-код (ES/DE/NL/...), а не название страны, и это
#    надёжнее HTML-блока Address, где страна текстом ПРОПУСКАЕТСЯ у немецких
#    центров (see #fallback_address) — видимо, потому что сайт немецкий и
#    Германия по умолчанию.
# 2. HTML .detail-address — фоллбек, когда JSON-LD вообще без address
#    (пример: robinson-soma-bay, где сайт международной сети не отдаёт
#    JSON-LD address). Первая строка — название точки, последняя — страна
#    ТОЛЬКО если это чисто буквенная строка (в остальных случаях страны в
#    разметке просто нет, см. выше).
# 3. .detail-region/.detail-season/.detail-contact/.detail-sports/
#    .detail-socialmedia — этих данных в JSON-LD нет вообще, только в
#    разметке. Все опциональны: блок целиком отсутствует в DOM, если поле
#    не заполнено в CMS (не пустой блок с пустым списком).
# 4. Telefon/Mobil/E-Mail/Webseite в .detail-contact — лейблы ВСЕГДА
#    по-немецки, даже на /en/ страницах (не тексты для локализации, а
#    статичные строки в шаблоне) — так что искать нужно немецкие лейблы
#    независимо от locale в URL.
#
# markers vs details: сырые поля адреса/контактов остаются плоскими
# значениями в details (для отображения как есть), а всё, что годится для
# фасетного поиска/сопоставления профилей между собой — сезон, спорт,
# гео-теги — идёт в markers (Marker/ProfileMarker), по той же схеме, что
# TripadvisorRestaurantParser использует для cuisines/features.
class VdwsParser
  MONTHS = %w[January February March April May June July August September October November December].freeze
  MONTH_RE = Regexp.union(MONTHS).freeze

  # Список стран строго из тех, что реально встречаются в фильтре
  # /en/watersport-center (<select name="...[country]">) — это и есть
  # полный домен значений addressCountry (ISO-код) на сайте, so no need for
  # a general-purpose ISO-3166 gem.
  COUNTRY_NAMES = {
    'AT' => 'Austria', 'BE' => 'Belgium', 'BR' => 'Brazil', 'CV' => 'Cape Verde',
    'HR' => 'Croatia', 'CY' => 'Cyprus', 'DK' => 'Denmark', 'DO' => 'Dominican Republic',
    'EG' => 'Egypt', 'FR' => 'France', 'DE' => 'Germany', 'GR' => 'Greece',
    'IL' => 'Israel', 'IT' => 'Italy', 'MV' => 'Maldives', 'MU' => 'Mauritius',
    'ME' => 'Montenegro', 'MA' => 'Morocco', 'NL' => 'Netherlands', 'PH' => 'Philippines',
    'PL' => 'Poland', 'PT' => 'Portugal', 'ZA' => 'South Africa', 'ES' => 'Spain',
    'LK' => 'Sri Lanka', 'CH' => 'Switzerland', 'TN' => 'Tunisia', 'TR' => 'Turkey'
  }.freeze

  def extract_profile_data(html, instructions: nil)
    doc = Nokogiri::HTML(html.to_s)
    ld = business_ld_json(doc)

    details = {}
    apply_ld_json(details, ld) if ld
    fallback_address(doc, details)
    apply_contact(doc, details)

    social = {}
    doc.css('.detail-socialmedia a[href]').each do |a|
      platform = a['title'].to_s.strip.downcase
      href = a['href'].to_s.strip
      next if platform.empty? || href.empty?

      social[platform] = href
    end
    details['social_media'] = social unless social.empty?

    markers = {}

    region = doc.css('.detail-region ul li').map { |li| li.text.strip }.reject(&:empty?)
    markers['region'] = region unless region.empty?

    markers['country'] = country_marker_value(details['country']) if details['country'].to_s.present?
    markers['city'] = details['city'] if details['city'].to_s.present?

    season_node = doc.at_css('.detail-season div')
    if season_node
      season_text = season_node.text.gsub(/\s+/, ' ').strip
      months = season_months(season_text)
      markers['season'] = months unless months.empty?
    end

    sport_types = doc.css('.detail-sports:not(.detail-internship) ul li').map { |li| li.text.strip }.reject(&:empty?)
    markers['sport_types'] = sport_types unless sport_types.empty?

    internship_offers = doc.css('.detail-sports.detail-internship ul li').map { |li| li.text.strip }.reject(&:empty?)
    markers['internship_offers'] = internship_offers unless internship_offers.empty?

    { 'markers' => markers, 'details' => details }
  end

  private

  # ISO-код (JSON-LD) -> человекочитаемое имя по COUNTRY_NAMES; если в
  # HTML-фоллбеке (fallback_address) страна УЖЕ текстом ("Egypt") — код там
  # не похож на 2 заглавные буквы, оставляем как есть.
  def country_marker_value(country)
    country.match?(/\A[A-Z]{2}\z/) ? COUNTRY_NAMES.fetch(country, country) : country
  end

  # "April – October" -> April..October, "all-season" -> все 12 месяцев,
  # один месяц в тексте -> он один, ничего не узнали -> [] (сезон при этом
  # остаётся виден в исходном тексте региона/страницы, просто не размечаем).
  def season_months(season_text)
    return [] if season_text.blank?

    normalized = season_text.downcase
    return MONTHS.dup if normalized.include?('all-season') || normalized.include?('all season') ||
                          normalized.include?('year-round') || normalized.include?('year round')

    matches = season_text.scan(MONTH_RE).map { |m| MONTHS.find { |canonical| canonical.casecmp(m).zero? } }
    return [] if matches.empty?
    return [matches.first] if matches.size == 1

    start_index = MONTHS.index(matches.first)
    end_index = MONTHS.index(matches.last)

    if start_index <= end_index
      MONTHS[start_index..end_index]
    else
      MONTHS[start_index..] + MONTHS[..end_index]
    end
  end

  def business_ld_json(doc)
    doc.css('script[type="application/ld+json"]').each do |script|
      data = begin
        JSON.parse(script.text)
      rescue JSON::ParserError
        next
      end
      return data if data.is_a?(Hash) && data['@type'] == 'LocalBusiness'
    end
    nil
  end

  def apply_ld_json(details, ld)
    details['phone'] = ld['telephone'] if ld['telephone'].to_s.present?
    details['fax'] = ld['faxNumber'] if ld['faxNumber'].to_s.present?
    details['email'] = ld['email'] if ld['email'].to_s.present?

    geo = ld['geo'] || {}
    details['latitude'] = geo['latitude'] if geo['latitude'].to_s.present?
    details['longitude'] = geo['longitude'] if geo['longitude'].to_s.present?

    opening_hours = ld['openingHours']
    details['opening_hours'] = opening_hours if opening_hours.is_a?(Array) && !opening_hours.empty?

    addr = ld['address'] || {}
    details['street'] = addr['streetAddress'] if addr['streetAddress'].to_s.present?
    details['postal_code'] = addr['postalCode'] if addr['postalCode'].to_s.present?
    details['city'] = addr['addressLocality'] if addr['addressLocality'].to_s.present?
    details['country'] = addr['addressCountry'] if addr['addressCountry'].to_s.present?
  end

  # Фоллбек только для того, чего не хватило из JSON-LD (обычно вообще всё
  # есть, кроме случаев вроде robinson-soma-bay без address в JSON-LD).
  def fallback_address(doc, details)
    addr_node = doc.at_css('.detail-address')
    return unless addr_node

    lines = addr_node.css('> div').map { |d| d.text.strip }.reject(&:empty?)
    return if lines.empty?

    details['address_name'] ||= lines[0]
    rest = lines[1..] || []
    return if rest.empty?

    if rest.size > 1 && rest.last.match?(/\A[\p{L}\s.'-]+\z/) && !details['country']
      details['country'] = rest.pop
    end

    details['street'] = rest[0] if rest[0] && !details['street']
    details['city'] = rest[1..].join(', ') if rest[1] && !details['city']
  end

  def apply_contact(doc, details)
    contact = doc.at_css('.detail-contact')
    return unless contact

    lines = contact.css('div')

    mobile_div = lines.find { |d| d.text.strip.start_with?('Mobil') }
    details['mobile'] = mobile_div.text.split(':', 2)[1]&.strip if mobile_div

    website_div = lines.find { |d| d.text.strip.start_with?('Webseite') }
    website = website_div&.at_css('a')&.[]('href')
    details['website'] = website if website

    return if details['phone'] && details['email']

    unless details['phone']
      phone_div = lines.find { |d| d.text.strip.start_with?('Telefon') }
      details['phone'] = phone_div.text.split(':', 2)[1]&.strip if phone_div
    end

    unless details['email']
      email_div = lines.find { |d| d.text.strip.start_with?('E-Mail') }
      details['email'] = email_div.text.split(':', 2)[1]&.strip if email_div
    end
  end
end
