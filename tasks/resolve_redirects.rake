require 'net/http'

# Некоторые сайты (например google.com — короткие ссылки вида
# https://maps.app.goo.gl/...) хранятся в Profile#url в виде, который сам
# браузер разворачивает в другой, канонический URL при переходе. Расширение
# tools/chrome-profile-parser шлёт на /api/parse именно итоговый (уже
# развёрнутый) URL страницы, поэтому Profile.find_by(url:) с исходной
# короткой ссылкой не матчится. app.rb дополнительно ищет по
# Profile#redirected_to — эта задача его заполняет.
def resolve_final_url(url, limit = 5)
  return nil if limit == 0

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
    resolve_final_url(next_uri.to_s, limit - 1)
  else
    uri.to_s
  end
rescue StandardError => e
  puts "  Ошибка: #{e.class}: #{e.message}"
  nil
end

namespace :profiles do
  desc "Резолвит редиректящие URL профилей в redirected_to, чтобы /api/parse мог найти Profile по итоговому URL (rake profiles:resolve_redirects [site=google.com])"
  task :resolve_redirects do
    site = Site.find_by!(domain: ENV['site']) if ENV['site']

    scope = Profile.where(redirected_to: [nil, ''])
    scope = scope.where(site_id: site.id) if site

    puts "Найдено #{scope.count} профилей без redirected_to#{site ? " (site: #{site.domain})" : ''}"

    scope.find_each do |profile|
      final_url = resolve_final_url(profile.url)

      if final_url.nil?
        puts "##{profile.id}: не удалось разрешить #{profile.url}"
      elsif final_url == profile.url
        puts "##{profile.id}: без редиректа"
      else
        profile.update!(redirected: true, redirected_to: final_url)
        puts "##{profile.id}: #{profile.url} -> #{final_url}"
      end
    end
  end
end
