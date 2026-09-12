require 'net/http'

# Разворачивает редиректящий URL (например короткие ссылки Google Maps
# https://maps.app.goo.gl/...) в итоговый канонический адрес, следуя по
# Location-заголовкам без спуфинга User-Agent (спуфленный Chrome UA у
# Google Maps ведёт на GDPR-consent-стену вместо самой карточки места —
# без UA получается чистый 1-хоповый редирект прямо на maps.google.com).
#
# Используется и из rake-таска (tasks/resolve_redirects.rake, разовый
# прогон по всем существующим профилям), и из Profile-модели (авто-резолв
# при создании/изменении google.com-профиля, см. app/models/profile.rb).
module RedirectResolver
  def self.resolve_final_url(url, limit: 5)
    return nil if limit <= 0 || url.to_s.empty?

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 10
    http.read_timeout = 10

    response = http.request(Net::HTTP::Get.new(uri.request_uri))

    case response
    when Net::HTTPRedirection
      next_uri = URI.parse(response['location'])
      next_uri = uri.merge(next_uri) if next_uri.relative?
      resolve_final_url(next_uri.to_s, limit: limit - 1)
    else
      uri.to_s
    end
  rescue StandardError => e
    puts "RedirectResolver: #{e.class}: #{e.message} (url=#{url})"
    nil
  end
end
