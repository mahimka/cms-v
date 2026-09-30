class RoutesHistory < App

  # Если ни Routes, ни RoutesLast не нашли Page под этим uri — ищем в
  # History (редиректы со старых адресов, см. app/models/history.rb) и
  # редиректим на new_uri тем кодом, что задан в записи (301/302/307/308).
  # Если и там ничего — pass дальше, в RoutesLost (см. app.rb/config.ru —
  # он самый последний, блок ботов + запись потери + честный 404).
  get '*' do |uri|
    history = History.find_by(old_uri: uri)

    pass unless history

    redirect history.new_uri, history.redirect_code
  end

end
