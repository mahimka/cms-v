require 'nokogiri'

# Извлекает rating/review_count/price_range из HTML-снапшота карточки
# Google Maps (site.domain == 'google.com') без AI.
#
# Публичный метод повторяет сигнатуру DeepseekClient#extract_profile_data
# (см. lib/parsers/tripadvisor_restaurant_parser.rb) — этот класс можно
# передать как client: в SnapShotParser.new, вся остальная логика (merge в
# profile.details, синхронизация profile.rating/review_count,
# parsed/parsed_at) отработает без изменений.
#
# Карточка Google Maps — SPA: rating/review_count/price рендерятся JS-ом уже
# ПОСЛЕ document_idle, отдельным асинхронным запросом (расширение
# tools/chrome-profile-parser теперь ждёт реальной отрисовки перед захватом
# outerHTML — см. waitForRenderedContent в content.js). JSON-LD Google, в
# отличие от TripAdvisor, не отдаёт — источник только видимый текст.
#
# Сверено на 8 реальных снапшотах (рестораны Изолы/Копра). Формат в верхней
# части карточки строго одинаковый на всех восьми:
#   "<Название>4,6(1 077)...Подробнее…·15–20 €Ресторан·Обзор..."
# т.е. рейтинг с запятой и число отзывов в скобках идут СРАЗУ друг за
# другом без пробела, сразу после названия заведения, а цена — вскоре
# после них, до категории заведения. Число отзывов Google разбивает по
# тысячам через NBSP (U+00A0), а не через обычный пробел — текст поэтому
# сначала нормализуется.
#
# Цену ищем ТОЛЬКО в куске текста сразу после рейтинга (см. HEADER_WINDOW),
# а не по всей странице: ниже на той же странице есть гистограмма разброса
# цен ("30–35 €35–40 €40–45 €45–50 €50 €+" — это "сколько платили другие",
# не текущая цена заведения) и цены "похожих мест" в конце страницы, которые
# по формату неотличимы от настоящей цены заведения.
class GoogleMapsParser
  RATING_AND_REVIEW_RE = /([0-5][.,]\d)\((\d[\d\s]*)\)/
  PRICE_RANGE_RE = /(\d{1,3}\s?[–-]\s?\d{1,3}\s?€)/
  PRICE_SINGLE_RE = /(\d{1,3}\s?€\+?)/
  PRICE_LEVEL_RE = /€{1,4}/
  HEADER_WINDOW = 200

  def extract_profile_data(html, instructions: nil)
    doc = Nokogiri::HTML(html.to_s)
    doc.css('script, style, noscript').remove
    text = doc.text.tr(" ", ' ').gsub(/\s+/, ' ').strip

    details = {}

    match = RATING_AND_REVIEW_RE.match(text)
    if match
      details['rating'] = match[1].tr(',', '.')
      details['review_count'] = match[2].strip

      header_tail = text[match.end(0), HEADER_WINDOW].to_s
      price = find_price(header_tail)
      details['price_range'] = price if price
    end

    { 'markers' => {}, 'details' => details }
  end

  private

  # Диапазон ("15–20 €") приоритетнее одиночной цены ("50 €+" — у заведений
  # без разброса цен), а одиночная цена приоритетнее просто уровня цены
  # (€/€€/€€€), который ничего не говорит о конкретной сумме.
  def find_price(text)
    text[PRICE_RANGE_RE, 1]&.strip ||
      text[PRICE_SINGLE_RE, 1]&.strip ||
      text[PRICE_LEVEL_RE]
  end
end
