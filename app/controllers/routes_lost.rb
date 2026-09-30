# Самый последний контроллер в цепочке (см. `use ... ` в app.rb — порядок
# важен) — сюда попадает запрос, который не обработали ни Routes (нет
# Page с таким uri), ни RoutesLast (не подошёл ни один redirect-паттерн),
# ни RoutesHistory (нет ручного/автоматического old_uri -> new_uri).
# Дальше только 404.
class RoutesLost < App

  get '*' do |uri|
    path = request.path_info

    # Сканеры уязвимостей (wp-login, .env, .git и т.п.) — сразу 404, без
    # записи в lost-url лог: их тысячи одинаковых, толку от анализа ноль,
    # а сигнал от настоящих потерянных страниц в них утонет.
    halt 404, erb(:"404", layout: false) if BLOCKED_PATHS.any? { |regex| regex.match?(path) }

    LostUrlLogger.record(path: path, referrer: request.referrer, ip: request.ip)

    halt 404, erb(:"404", layout: false)
  end

end
