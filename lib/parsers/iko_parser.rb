require 'json'
require 'date'

# Извлекает markers/details для профиля на ikointl.com (site.domain ==
# 'ikointl.com') — но НЕ из HTML: ikointl.com отдаёт на страницу школы
# пустой Angular-шелл (весь контент рисуется JS-ом из отдельного публичного
# JSON API на d8.ikointl.com, Drupal 10 backend). Поэтому вход сюда —
# не HTML, а уже готовый JSON-ответ
# GET https://d8.ikointl.com/api/v1/school_details.json/{nid}?_format=json&langcode=en
# (см. project/tasks/fetch_iko.rb — там же матчинг url_alias -> Profile.url,
# т.к. эндпоинт отдаёт данные по numeric nid, а не по slug).
#
# Публичный метод сохраняет сигнатуру extract_profile_data(html,
# instructions:), чтобы работать через тот же SnapShotParser, что и
# остальные детерминированные парсеры (см. lib/parsers/booking_parser.rb) —
# просто "html" тут на самом деле сырой JSON-текст.
#
# Чего в этом API НЕТ (было в старых 199 entity из другого источника,
# см. обсуждение) — телефон/whatsapp почти всегда пустые
# (field_contact_person), точные типы уроков (Beginner/Advanced Lessons),
# сертификация "IKO PRO Center", список языков. Это осталось для ручного
# заполнения.
class IkoParser
  MONTHS = %w[January February March April May June July August September October November December].freeze

  def extract_profile_data(json_text, instructions: nil)
    data = begin
      JSON.parse(json_text.to_s)
    rescue JSON::ParserError
      nil
    end

    record = data.is_a?(Array) ? data.first : nil
    return { 'markers' => {}, 'details' => {} } unless record

    details = {}
    markers = {}

    details['name'] = record['title'] if record['title'].to_s.present?
    details['description'] = strip_tags(record['body']) if record['body'].to_s.present?
    details['street'] = record['field_school_address_address_line1'] if record['field_school_address_address_line1'].to_s.present?

    city = record['field_school_address_locality'].to_s.strip
    details['city'] = city unless city.empty?

    details['postal_code'] = record['field_school_address_postal_code'] if record['field_school_address_postal_code'].to_s.present?

    region = (record['field_school_address_administrative_area_name'] || record['field_school_address_administrative_area']).to_s.strip
    region = '' if region.match?(/\A\*+\z/) # плейсхолдер "*" в паре записей вместо пустого поля
    details['region'] = region unless region.empty?

    country = record['field_school_address_country_name'].to_s.strip
    details['country'] = country unless country.empty?

    gps = record['field_school_gps'] || {}
    details['latitude'] = gps['lat'] if gps['lat']
    details['longitude'] = gps['lon'] if gps['lon']

    contact = record['field_contact_person'].to_s.strip
    details['email'] = contact if contact.include?('@')

    details['tag_line'] = record['field_tag_line'] if record['field_tag_line'].to_s.present?

    details['rating'] = record['rate_value'] if record['rate_value'].to_s.present?
    details['review_count'] = record['rate_count'] if record['rate_count'].to_s.present?
    %w[equipment_rating safety_rating teaching_rating school_service_rating].each do |key|
      details[key] = record[key] if record[key].to_s.present?
    end

    details['membership_tier'] = record['roles_target_id'] if record['roles_target_id'].to_s.present?

    logo = best_image(record['field_school_logo'])
    details['logo'] = logo if logo

    cover = best_image(record['field_school_cover'])
    details['cover'] = cover if cover

    gallery = Array(record['field_school_gallery']).map { |img| best_image(img) }.compact
    details['gallery'] = gallery unless gallery.empty?

    details['iko_nid'] = record['nid'] if record['nid'].to_s.present?

    markers['country'] = country unless country.empty?
    markers['region'] = region unless region.empty?
    markers['city'] = city unless city.empty?

    facilities = Array(record['field_school_facilities']).map { |f| f['title'] }.compact
    markers['facilities'] = facilities unless facilities.empty?

    brands = Array(record['field_school_brands']).map { |b| b['title'] || b['name'] }.compact
    markers['brands'] = brands unless brands.empty?

    markers['membership_tier'] = record['roles_target_id'] if record['roles_target_id'].to_s.present?

    months = Array(record['field_seasons']).flat_map { |s| season_months(s['field_season_start_date'], s['field_season_end_date']) }.uniq
    markers['season'] = months unless months.empty?

    { 'markers' => markers, 'details' => details }
  end

  private

  def strip_tags(text)
    text.to_s.gsub(/<[^>]+>/, '').gsub(/\s+/, ' ').strip
  end

  # Логотип/обложка/фото приходят как хэш {стиль => url} разных размеров —
  # берём самый крупный доступный, без привязки к конкретному набору
  # ключей (у логотипа они одни, у обложки другие).
  def best_image(image_hash)
    return nil unless image_hash.is_a?(Hash)

    PREFERRED_IMAGE_KEYS.each { |key| return image_hash[key] if image_hash[key].present? }
    image_hash.values.find(&:present?)
  end

  PREFERRED_IMAGE_KEYS = %w[max_2600x2600 header_fhd landscape_fhd school_square_hd square_hd header_hd landscape_hd].freeze

  def season_months(start_date, end_date)
    return [] if start_date.blank? || end_date.blank?

    start = Date.parse(start_date) rescue nil
    finish = Date.parse(end_date) rescue nil
    return [] unless start && finish

    start_index = start.month - 1
    end_index = finish.month - 1

    # Диапазон длиной год и больше (или свёрнутый в один день на границе) -
    # считаем круглогодичным, а не одним месяцем на стыке дат.
    return MONTHS.dup if (finish - start) >= 365

    if start_index <= end_index
      MONTHS[start_index..end_index]
    else
      MONTHS[start_index..] + MONTHS[..end_index]
    end
  end
end
