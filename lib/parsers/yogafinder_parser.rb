require 'nokogiri'
require 'faraday'
require_relative '../yogatracking_throttle'

# Извлекает name/address/phone/description/markers (country/region/
# locality/styles) из HTML профиля на yogafinder.com
# (yoga.cfm?yoganumber=N).
#
# Сайт древний (table-based вёрстка, невалидный HTML — часть тегов не
# закрыта), поэтому селекторы завязаны не на позицию в таблице (Nokogiri
# может по-разному перестроить дерево от страницы к странице), а на
# устойчивые маркеры: <title> (имя), уникальный класс
# span.descriptionstyle (описание), текст "Tel:" внутри div.insidetext
# (телефон), href хлебных крошек (country/region/locality). Сверено на 3
# живых профилях (Ireland без региона, US со штатом, третий — с "Online
# Yoga"-ссылкой прямо в HTML в довесок к Website-кнопке).
#
# region в markers бывает не у всех стран (только там, где на сайте есть
# отдельный уровень "штат/провинция" — США и немногие другие) — просто
# отсутствует в хэше, если в хлебных крошках только 2 уровня (country,
# locality) вместо 3.
#
# website — кнопка "Website" на странице (div.boxed) ведёт не на сам
# сайт, а на yogatracking.cfm?yoganumber=N — редирект-трекер, отдающий
# 302 с реальным адресом в заголовке Location. #resolve_website делает
# этот один redirect-хоп сам (не грузит сам трекер как страницу) и затем
# HEAD-запрос на итоговый адрес — website попадает в результат, только
# если сайт реально ответил (мёртвый домен -> nil), как и просили.
#
# Сам redirect-хоп идёт через YogaTrackingThrottle (см.
# lib/yogatracking_throttle.rb) — у трекера общий на весь IP rate-limit,
# без централизованного троттлинга параллельные потоки (см.
# tasks/yogafinder_profile_ids.rake, parse_profiles) выбивают его за
# секунды и молча портят website на всё оставшееся до конца прогона.
class YogafinderParser
  BASE_URL = "https://www.yogafinder.com"

  # "/" — тоже разделитель (реальный пример: "Kundalini Yoga/Meditation/
  # Hatha/Flow/Vinyasa" одной строкой без пробелов вокруг "/").
  STYLE_SPLIT_RE = %r{\s*(?:,|&|/|\band\b)\s*}i
  PHONE_RE = /Tel:\s*([\d][\d\-\+\(\)\s]*\d)/i

  # Заголовок, который отдаёт /yoga.cfm для несуществующего/удалённого
  # yoganumber — вместо 404 сайт молча показывает generic-страницу с этим
  # <title> (весь остальной контент пустой). Проверено на нескольких id
  # из старого импорта old_yogamela.com — за прошедшие годы часть листингов
  # с сайта пропала.
  NOT_FOUND_TITLE = "Look for Yoga Events and Yoga Classes on YogaFinder"

  def initialize(connection: nil)
    @connection = connection || Faraday.new do |f|
      f.options.timeout = 10
      f.options.open_timeout = 5
      f.headers['User-Agent'] = 'Mozilla/5.0 (compatible; YogamelaImportBot/1.0)'
    end
  end

  # Полный разбор одного профиля по номеру (тому самому N из
  # /yoga.cfm?yoganumber=N) — GET страницы + parse_html + резолв website.
  def parse(yoganumber)
    response = @connection.get("#{BASE_URL}/yoga.cfm", yoganumber: yoganumber)
    data = parse_html(response.body)

    tracking_path = data.delete('website_tracking_path')
    data['website'] = tracking_path ? resolve_website(tracking_path) : nil

    data
  end

  # Чистое извлечение из уже полученного HTML, без единого сетевого
  # запроса — удобно для тестов и для повторной обработки уже
  # сохранённых снапшотов. website сюда не входит (это отдельный поход в
  # сеть, за which website_tracking_path и оставлен в результате — см.
  # #parse/#resolve_website); звать #resolve_website(data['website_tracking_path'])
  # отдельно, если он нужен.
  def parse_html(html)
    doc = Nokogiri::HTML(html.to_s)
    name = extract_name(doc)

    return { 'name' => name, 'not_found' => true } if name == NOT_FOUND_TITLE

    {
      'name' => name,
      'address' => extract_address(doc),
      'phone' => extract_phone(doc),
      'description' => extract_description(doc),
      'markers' => extract_markers(doc),
      'website_tracking_path' => extract_tracking_path(doc)
    }
  end

  # tracking_path — href кнопки "Website" со страницы профиля (например
  # "yogatracking.cfm?yoganumber=55790"). Возвращает URL реального сайта,
  # если трекер его отдал И сайт ответил — иначе nil. Может бросить
  # YogaTrackingThrottle::BlockedError, если трекер сейчас забанен и это
  # не удалось разрулить троттлингом+ретраями внутри throttle-модуля —
  # вызывающий код (parse_profiles) в этом случае должен НЕ записывать
  # website=nil, а считать profile необработанным и попробовать позже.
  def resolve_website(tracking_path)
    return nil if tracking_path.blank?

    url = YogaTrackingThrottle.resolve(tracking_path, connection: @connection)
    return nil if url.blank?

    url = normalize_scheme(url)
    site_alive?(url) ? url : nil
  end

  private

  # Location у части бизнесов приходит как "Http://domain.com" (заглавная
  # H — так когда-то ввели URL в форме на yogafinder.com, дальше он просто
  # хранится как есть). Faraday/faraday-net_http почему-то не узнают в
  # таком scheme http/https и не могут определить host — падают с
  # ConnectionFailed (host/port уходят в nil), а site_alive? эту ошибку
  # тихо ловит как "сайт мёртв" (проверено на живую: yoganumber=1591,
  # iDoYoga.com — сайт рабочий, ломался именно на регистре scheme).
  def normalize_scheme(url)
    url.sub(%r{\Ahttps?://}i) { |m| m.downcase }
  end

  # HEAD — быстрее, но часть сайтов его не поддерживает (405/501) —
  # тогда пробуем обычный GET, прежде чем сдаться.
  def site_alive?(url)
    response = @connection.head(url)
    return true if response.status < 400

    response = @connection.get(url)
    response.status < 400
  rescue Faraday::Error
    false
  end

  def extract_name(doc)
    doc.at_css('title')&.text&.squeeze(' ')&.strip
  end

  # Три div.insidetext на странице всегда в одном порядке: имя+кнопки,
  # адрес, телефон — адрес просто второй. Раньше искали "тот, что без
  # .boxed-кнопок и без Tel:" — ломалось на листингах БЕЗ Website/Online
  # Yoga кнопок вообще: тогда у name-узла тоже нет .boxed, и find()
  # ошибочно забирал его (имя) вместо адреса (проверено на
  # yoganumber=57053, Aya Yoga Oasis — address вернулся как "Aya Yoga
  # Oasis").
  def extract_address(doc)
    node = doc.css('div.insidetext')[1]
    node&.text.to_s.gsub(/\s+/, ' ').strip.presence
  end

  def extract_phone(doc)
    node = doc.css('div.insidetext').find { |n| n.text =~ /Tel:/i }
    node&.text.to_s[PHONE_RE, 1]&.strip
  end

  def extract_description(doc)
    doc.at_css('span.descriptionstyle')&.text&.gsub(/\s+/, ' ')&.strip.presence
  end

  # Список стилей лежит в td.thirdcol в той же строке, что и имя/кнопки —
  # ПЕРВЫЙ по счёту. thirdcol на странице встречается ещё раз-два дальше
  # (у кнопки Email — text() там буквально "Email", у "Update listing" —
  # аналогично), поэтому брать "первый НЕПУСТОЙ" неверно: если у листинга
  # реально нет стилей (пусто), код проваливался до следующего thirdcol и
  # ошибочно забирал "Email"/"Update listing" как будто это стиль
  # (проверено на реальных данных: 1142 и 91 таких "стилей" в проде).
  def extract_styles(doc)
    text = doc.css('td.thirdcol').first&.text&.strip
    return [] if text.blank?

    text.split(STYLE_SPLIT_RE).map(&:strip).reject(&:empty?)
  end

  # Хлебные крошки: первая ссылка — всегда статичная "Country" (на
  # /yogasearch.cfm, не значение) — пропускаем. Остальные классифицируем
  # по href, не по позиции — так надёжнее (region есть не у всех стран,
  # позиция плывёт: 2 крошки без region, 3 — с ним).
  def extract_markers(doc)
    crumbs = doc.at_css('div.breadcrumbscss')&.css('a').to_a
    markers = {}

    crumbs.each do |a|
      href = a['href'].to_s
      text = a.text.strip
      next if text.blank?

      if href.include?('yogaarea.cfm')
        markers['country'] = text
      elsif href.include?('yogacity.cfm') && href.include?('yogalocation=')
        markers['region'] = text
      elsif href.include?('yoga.cfm') && href.include?('yogacity=')
        markers['locality'] = text
      end
    end

    styles = extract_styles(doc)
    markers['styles'] = styles unless styles.empty?

    markers
  end

  def extract_tracking_path(doc)
    link = doc.css('a').find { |a| a.at_css('div.boxed')&.text&.strip == 'Website' }
    link && link['href']
  end
end
