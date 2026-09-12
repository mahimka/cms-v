require 'nokogiri'

# Извлекает rating/review_count/price_level со страницы заведения на
# Facebook (site.domain == 'facebook.com') без AI.
#
# Публичный метод повторяет сигнатуру DeepseekClient#extract_profile_data
# (см. lib/parsers/tripadvisor_restaurant_parser.rb) — этот класс можно
# передать как client: в SnapShotParser.new, вся остальная логика (merge в
# profile.details, синхронизация profile.rating/review_count,
# parsed/parsed_at) отработает без изменений.
#
# У Facebook нет "звёздного" рейтинга на страницах заведений — вместо этого
# "Рекомендовали: 80 % (27 отзывов)". По просьбе сохраняем это число как
# rating (0..100, а не 0..5, как у остальных сайтов) — единая колонка
# profile.rating общая для всех парсеров, единица измерения зависит от
# сайта, тут это % рекомендаций.
#
# price_level Facebook всегда рисует знаками доллара ($/$$/$$$), даже если
# сама валюта в других местах — €, это ограничение самого Facebook UI, а не
# ошибка парсера.
#
# Сверено на 6 реальных снапшотах (рестораны Изолы/Копра): у 5 из 6 есть
# "Рекомендовали: N % (M отзывов)" сразу после "Диапазон цен · $...", у
# одной страницы (Gostilna Korte, много подписчиков, но блока с рейтингом
# нет вообще на странице) — в этом случае ничего не извлекаем, это не баг,
# а отсутствие данных у самого Facebook. Число отзывов Facebook разбивает
# по тысячам через NBSP (U+00A0), а не через обычный пробел — текст поэтому
# сначала нормализуется.
class FacebookParser
  RATING_RE = /Рекомендовали:\s*(\d{1,3})\s*%\s*\((\d[\d\s]*)\s*отзыв/i
  PRICE_LEVEL_RE = /Диапазон цен\s*·\s*(\${1,4})/

  def extract_profile_data(html, instructions: nil)
    doc = Nokogiri::HTML(html.to_s)
    doc.css('script, style, noscript').remove
    text = doc.text.tr(" ", ' ').gsub(/\s+/, ' ').strip

    details = {}

    match = RATING_RE.match(text)
    if match
      details['rating'] = match[1]
      details['review_count'] = match[2].strip
    end

    price_level = text[PRICE_LEVEL_RE, 1]
    details['price_level'] = price_level if price_level

    { 'markers' => {}, 'details' => details }
  end
end
