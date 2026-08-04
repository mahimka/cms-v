module TranslationHelpers

  # Перевод произвольной UI-строки по ключу (например translation('_faq')).
  # Ищет Label с таким name и берёт Label#translation(lang); если такого
  # Label нет — возвращает сам key, чтобы вид не падал из-за отсутствующего
  # перевода.
  def translation(key, lang: nil)
    lang ||= @page&.lang || settings.home_language

    Label.find_by(name: key)&.translation(lang) || key
  end

end
