# Некоторые сайты (например google.com — короткие ссылки вида
# https://maps.app.goo.gl/...) хранятся в Profile#url в виде, который сам
# браузер разворачивает в другой, канонический URL при переходе. Расширение
# tools/chrome-profile-parser шлёт на /api/parse именно итоговый (уже
# развёрнутый) URL страницы, поэтому Profile.find_by(url:) с исходной
# короткой ссылкой не матчится. app.rb дополнительно ищет по
# Profile#redirected_to.
#
# Новые/изменённые google.com-профили резолвятся автоматически — см.
# Profile#resolve_google_maps_redirect (app/models/profile.rb). Эта задача
# нужна только для разового прогона по уже существующим профилям (например
# сразу после деплоя на сервер, где авто-резолв ещё не сработал ни разу) —
# см. lib/redirect_resolver.rb, общий с моделью код самого резолва.
namespace :profiles do
  desc "Резолвит редиректящие URL профилей в redirected_to, чтобы /api/parse мог найти Profile по итоговому URL (rake profiles:resolve_redirects [site=google.com])"
  task :resolve_redirects do
    site = Site.find_by!(domain: ENV['site']) if ENV['site']

    scope = Profile.where(redirected_to: [nil, ''])
    scope = scope.where(site_id: site.id) if site

    puts "Найдено #{scope.count} профилей без redirected_to#{site ? " (site: #{site.domain})" : ''}"

    scope.find_each do |profile|
      final_url = RedirectResolver.resolve_final_url(profile.url)

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
