require 'nokogiri'
require 'json'
require 'uri'

# Извлекает контакты (phone/email/address) и ссылки на соцсети со страницы
# официального сайта заведения (Link label == 'website') — без AI, тем же
# приёмом, что TripadvisorHotelParser/TripadvisorRestaurantParser
# (lib/parsers/tripadvisor_shared.rb): сперва JSON-LD (LocalBusiness/
# Organization), дальше tel:/mailto: ссылки и <a href> на известные домены
# соцсетей как фоллбек. В отличие от Tripadvisor-парсеров это обычный сайт
# заведения, а не одна и та же платформа — JSON-LD у него может вообще
# отсутствовать, поэтому DOM-фоллбек тут не запасной вариант "на всякий
# случай", а основной источник данных для большинства сайтов.
#
# Публичный метод — extract(html), возвращает { 'phone', 'email', 'address',
# 'social_links' => {label_name => url} }. Не пишет ничего в БД — этим
# занимается WebsiteScraper (lib/website_scraper.rb), который решает, что
# делать с уже существующими Link/Detail у entity.
class WebsitePageParser
  # label в таблице labels (см. LinkChecker/Link) -> паттерн домена. Список
  # ровно совпадает с уже заведёнными в БД child-лейблами link_labels
  # (facebook/instagram/x/youtube/linkedin) — см. db/main.db.
  SOCIAL_DOMAINS = {
    'facebook'  => /(?:facebook\.com|fb\.me)/i,
    'instagram' => /instagram\.com/i,
    'x'         => /(?:twitter\.com|x\.com)/i,
    'youtube'   => /(?:youtube\.com|youtu\.be)/i,
    'linkedin'  => /linkedin\.com/i,
    'telegram'  => /(?:t\.me|telegram\.me)/i,
    'whatsapp'  => /(?:wa\.me|whatsapp\.com)/i,
    'tiktok'    => /tiktok\.com/i,
  }.freeze

  # Share/intent-виджеты платформ, которые сайты вставляют в каждый футер
  # ("Поделиться в Facebook" и т.п.) — это не ссылка НА страницу заведения,
  # подхватывать её как social link не нужно.
  IGNORED_PATH_RE = %r{\A/(sharer|share|intent|dialog)(/|\z)}i

  # "email@domain" минимум с одной точкой в домене — отсекает битые/
  # JS-обфусцированные mailto (на реальных сайтах встречается href="mailto:x"
  # с настоящим адресом, подставляемым в onclick, а не в href).
  EMAIL_RE = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  def extract(html)
    doc = Nokogiri::HTML(html.to_s)
    biz = business_ld_json(doc)

    {
      'phone'        => extract_phone(doc, biz),
      'email'        => extract_email(doc, biz),
      'address'      => extract_address(biz),
      'social_links' => extract_social_links(doc, biz)
    }
  end

  private

  # Среди ld+json блоков страницы (Organization/WebSite/LocalBusiness и
  # т.п., может быть несколько) ищем тот, что реально описывает бизнес —
  # у него есть хотя бы одно из telephone/address/email. JSON-LD иногда
  # приходит массивом объектов или обёрнутым в @graph — разворачиваем оба
  # варианта.
  def business_ld_json(doc)
    doc.css('script[type="application/ld+json"]').each do |script|
      data = begin
        JSON.parse(script.text)
      rescue JSON::ParserError
        next
      end

      # Array(hash) разбирает Hash на пары [ключ, значение] — здесь нужно
      # ровно наоборот, обернуть одиночный объект в массив из одного элемента.
      nodes = data.is_a?(Array) ? data : [data]
      nodes = nodes.flat_map { |n| n.is_a?(Hash) ? (n['@graph'] || [n]) : [] }
      found = nodes.find { |n| n.is_a?(Hash) && (n['telephone'] || n['address'] || n['email']) }
      return found if found
    end
    nil
  end

  def extract_phone(doc, biz)
    value = (biz && biz['telephone']) || doc.at_css('a[href^="tel:"]')&.[]('href')&.sub(/\Atel:/, '')
    value&.strip.presence
  end

  def extract_email(doc, biz)
    biz_email = biz && biz['email']
    return biz_email if biz_email&.match?(EMAIL_RE)

    # Берём первый mailto: с валидным на вид адресом, а не просто первый
    # попавшийся — на реальных сайтах первая mailto-ссылка на странице
    # нередко битая (href="mailto:xxx", настоящий адрес подставляется
    # в onclick через JS, до которого мы не добираемся).
    doc.css('a[href^="mailto:"]').each do |a|
      value = a['href'].to_s.sub(/\Amailto:/, '').split('?').first&.strip
      return value if value&.match?(EMAIL_RE)
    end
    nil
  end

  def extract_address(biz)
    addr = biz && biz['address']
    return nil unless addr.is_a?(Hash)

    country = addr['addressCountry']
    country = country.is_a?(Hash) ? (country['name'] || country['@id']) : country

    parts = [addr['streetAddress'], addr['addressLocality'], addr['postalCode'], country]
    text = parts.compact.map(&:to_s).reject(&:empty?).join(', ')
    text.presence
  end

  def extract_social_links(doc, biz)
    urls = doc.css('a[href]').map { |a| a['href'] }
    urls.concat(Array(biz && biz['sameAs']))
    urls.compact!

    SOCIAL_DOMAINS.each_with_object({}) do |(label, domain_re), result|
      match = urls.find { |url| url =~ domain_re && meaningful_social_url?(url) }
      result[label] = match if match
    end
  end

  # Отсекает и share/intent-виджеты, и голый корень домена ("Подписывайтесь
  # на нас!" со ссылкой ровно на https://www.facebook.com, без страницы
  # заведения) — второе на практике встречается не реже первого.
  def meaningful_social_url?(url)
    uri = URI.parse(url)
    return false if uri.path.to_s =~ IGNORED_PATH_RE

    !uri.path.to_s.delete('/').empty?
  rescue URI::InvalidURIError
    false
  end
end
