require 'net/http'

# Проверка "жива ли ссылка" — GET (не HEAD: часть сайтов не умеет HEAD
# правильно, а для facebook/instagram и для эвристики "домен продаётся"
# всё равно нужен кусок body), с ручным прохождением редиректов (тот же
# приём, что в RedirectResolver, но здесь дополнительно нужен статус и
# body финального ответа, а не только itself финальный URL).
#
# Facebook/Instagram почти всегда отдают 200 даже на несуществующую
# страницу (просто login-стену/заглушку) — код ответа тут не индикатор,
# поэтому для них отдельно матчим текст заглушки в body.
#
# "Домен продаётся" — только эвристика по тексту (Sedo/GoDaddy/HugeDomains
# и т.п.), ложные срабатывания возможны — поэтому НЕ трогает alive,
# только дописывается в response как заметка для модератора.
#
# Используется и из tasks/links.rake (плановая проверка), и из кнопок в
# admin (entities/_links_fields.erb) — единая точка правды про то, что
# значит "ссылка мертва", у всех сайтов-проектов на этой кодовой базе.
module LinkChecker
  # Не лимит "сколько матчить" (матчим по всему телу — у facebook реальный
  # маркер "Content Isn't Available" лежит далеко за условными 50KB,
  # там перед ним ещё сотни KB inline-CSS) — а защита от патологии
  # (страница окажется гигабайтным файлом): страховочно обрываем скачивание,
  # если тело набрало больше этого объёма.
  MAX_BODY_BYTES = 5_000_000
  MAX_REDIRECTS = 5

  DEAD_CONTENT_PATTERNS = {
    'facebook'  => [/Content (Isn.t|Not) Available/i, /This content isn.t available right now/i, /page you requested cannot be displayed/i],
    'instagram' => [/Sorry, this page isn.t available/i, /Page Not Found/i],
  }.freeze

  FOR_SALE_PATTERNS = [
    /domain (is|may be) for sale/i,
    /buy this domain/i,
    /this domain is (available|parked)/i,
    /make an offer/i,
    /HugeDomains/i,
    /Sedo\.com/i,
    /Afternic/i,
    /BuyDomains/i,
    # GoDaddy-парковка ("oceansports.com is parked free, courtesy of
    # GoDaddy.com") не попадала под "this domain is parked" — имя домена
    # стоит между "is" и "parked", а не "this domain".
    /is parked (free|for free)/i,
    /get this domain/i,
    /courtesy of godaddy/i,
  ].freeze

  Result = Struct.new(:status_code, :final_url, :redirected, :body, :error, keyword_init: true)

  # Один повторный прогон при сетевой ошибке или 5xx — защита от разового
  # сбоя; 4xx (в т.ч. 404) — детерминированный ответ, повтор не изменит.
  def self.check(url)
    result = perform_check(url)

    if result.error || (result.status_code && result.status_code >= 500)
      sleep 1
      result = perform_check(url)
    end

    result
  end

  # apply! — синхронный путь для одиночной ссылки (кнопки в админке).
  # apply_result! — та же логика поверх уже готового результата check(),
  # чтобы вызывающий (tasks/links.rake) мог сделать check() снаружи
  # ActiveRecord::Base.connection_pool.with_connection и не держать
  # соединение с БД занятым на всё время сетевого запроса.
  def self.apply!(link)
    apply_result!(link, check(link.url))
  end

  def self.apply_result!(link, result)
    label_name = link.label&.name

    link.checked_at = Time.current

    if result.error
      link.response = "error: #{result.error}"
      link.alive = false
      link.redirected = false
      link.redirected_to = nil
    else
      link.redirected = result.redirected
      link.redirected_to = result.redirected ? result.final_url : nil

      if result.status_code != 200
        link.response = result.status_code.to_s
        link.alive = false
      elsif dead_content?(label_name, result.body)
        link.response = "200 (похоже на несуществующую страницу)"
        link.alive = false
      else
        note = for_sale?(result.body) ? " (возможно домен продаётся — проверить вручную)" : ""
        link.response = "200#{note}"
        link.alive = true
      end
    end

    link.save!
    link
  end

  def self.dead_content?(label_name, body)
    return false if body.blank? || label_name.blank?

    patterns = DEAD_CONTENT_PATTERNS[label_name]
    return false unless patterns

    patterns.any? { |p| body =~ p }
  end

  def self.for_sale?(body)
    return false if body.blank?

    FOR_SALE_PATTERNS.any? { |p| body =~ p }
  end

  def self.perform_check(url, limit: MAX_REDIRECTS, redirected: false)
    return Result.new(error: "too many redirects") if limit <= 0

    # Link#url теперь стрипается на save (см. app/models/link.rb), но в базе
    # ещё могут быть старые записи с пробелом по краям — URI.parse от него
    # падает с InvalidURIError вместо содержательной ошибки.
    uri = URI.parse(url.to_s.strip)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 10
    http.read_timeout = 10

    status_code = nil
    location = nil
    body = +""

    request = Net::HTTP::Get.new(uri.request_uri)
    # Без этого facebook/instagram (и многие другие сайты) локализуют
    # страницу по IP сервера — например текст "Content Isn't Available"
    # приходит по-словенски вместо английского, и DEAD_CONTENT_PATTERNS
    # ниже никогда не совпадут.
    request['Accept-Language'] = 'en-US,en;q=0.9'

    # break из read_body до конца потока на этой версии net/http ненадёжен
    # (на chunked — EOFError, на gzip — NoMethodError в Inflater при
    # cleanup после блока) — поэтому останавливаем скачивание через raise,
    # а не break, если тело переросло страховочный MAX_BODY_BYTES.
    http.request(request) do |response|
      status_code = response.code.to_i
      location = response['location']
      response.read_body do |chunk|
        body << chunk
        raise "body too large (> #{MAX_BODY_BYTES} bytes)" if body.bytesize > MAX_BODY_BYTES
      end
    end

    if status_code.between?(300, 399) && location.present?
      next_uri = URI.parse(location)
      next_uri = uri.merge(next_uri) if next_uri.relative?
      return perform_check(next_uri.to_s, limit: limit - 1, redirected: true)
    end

    Result.new(status_code: status_code, final_url: url, redirected: redirected, body: body.force_encoding('UTF-8').scrub)
  rescue StandardError => e
    Result.new(error: "#{e.class}: #{e.message}")
  end
end
