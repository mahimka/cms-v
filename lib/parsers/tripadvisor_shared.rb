require 'nokogiri'
require 'json'

# Общие для всех TripAdvisor-парсеров (ресторан/отель/...) куски: поиск
# JSON-LD блока самого заведения, сборка адреса, "Review Summary"-чипсы
# рядом с рейтингом (Food/Cleanliness/Location/...). Всё остальное —
# специфика конкретного типа страницы — живёт в самих парсерах.
module TripadvisorPageHelpers
  COUNTRY_NAMES = { 'IT' => 'Italy' }.freeze

  DOLLAR_RANGE = /\A\$+(\s*[-–]\s*\$+)?\z/

  # Среди ld+json блоков страницы (обычно есть ещё Organization и
  # BreadcrumbList) ищем тот, что описывает само заведение — у него одного
  # есть address.
  def business_ld_json(doc)
    doc.css('script[type="application/ld+json"]').each do |script|
      data = begin
        JSON.parse(script.text)
      rescue JSON::ParserError
        next
      end
      return data if data.is_a?(Hash) && data['address']
    end
    nil
  end

  def format_address(addr)
    return nil unless addr

    country = addr.dig('addressCountry', 'name')
    country = COUNTRY_NAMES.fetch(country, country) if country

    parts = [
      addr['streetAddress'],
      addr['addressLocality'],
      [addr['postalCode'], addr['addressRegion']].compact.reject(&:empty?).join(' '),
      country
    ]

    full = parts.compact.reject(&:empty?).join(', ')
    full.empty? ? nil : full
  end

  # "$", "$$ - $$$", "$$$$ (Based on ...)" -> длина самого длинного набора
  # $ подряд (1..4), или nil, если строки нет / она не в $-формате.
  def dollar_tier(symbols)
    return nil unless symbols

    runs = symbols.scan(/\$+/)
    return nil if runs.empty?

    runs.map(&:length).max
  end

  # <div role="button"> с ровно одной svg-иконкой и двумя короткими span —
  # первый span это группа (Food/Cleanliness/Location/Value/...), второй —
  # значение (Fresh/Attentive/Reasonable/...). На реальных страницах
  # ресторанов и отелей это единственные role=button такой формы (0 ложных
  # срабатываний на 962+542 проверенных снапшотах), поэтому не нужно
  # опираться на хешированные CSS-классы TripAdvisor. Есть только когда у
  # заведения достаточно отзывов, чтобы TripAdvisor это посчитал (~2%
  # страниц).
  def review_summary_markers(doc)
    doc.css('div[role="button"]').filter_map do |btn|
      spans = btn.css('span')
      next if btn.css('svg').size != 1 || spans.size != 2

      texts = spans.map { |s| s.text.strip }
      next if texts.any?(&:empty?) || texts.any? { |t| t.split.size > 3 }

      "RS_#{texts[0].gsub(/\s+/, '_')}_#{texts[1].gsub(/\s+/, '_')}"
    end
  end
end
