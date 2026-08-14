class RoutesHistory < App

  # Последний рубеж перед настоящим 404: если ни Routes, ни RoutesLast
  # не нашли Page под этим uri — ищем в History (редиректы со старых
  # адресов, см. app/models/history.rb) и редиректим на new_uri тем
  # кодом, что задан в записи (301/302/307/308). Если и там ничего —
  # честный 404.
  get '*' do |uri|
    history = History.find_by(old_uri: uri)

    halt 404, "Not Found #{uri}\n" unless history

    redirect history.new_uri, history.redirect_code
  end

end
