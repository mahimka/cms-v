# Оркестрация перевода Page через GeminiClient: создание отсутствующих
# языковых версий и точечная "протолкнуть перевод одного поля" в уже
# существующие переводы (см. Page::TRANSLATABLE_FIELDS).
#
# GeminiClient сам по себе ничего не знает про Page/переводы — вся
# специфика модели (dup, MASTER_ONLY_FIELDS, parent-переводов) здесь.
class PageTranslator
  Result = Struct.new(:lang, :page, :error, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def initialize(gemini_client:, languages:)
    @gemini = gemini_client
    @languages = languages.map(&:to_s)
  end

  # Создаёт переводы мастер-страницы на все настроенные языки, для
  # которых перевода ещё нет. Уже существующие переводы не трогает.
  #
  # Если у страницы есть родитель, а у родителя ещё нет перевода на
  # нужный язык — это ожидаемо провалит validation (translation_parent_
  # must_match_master_parent), ошибка попадёт в Result, а не прервёт
  # обработку остальных языков.
  def create_missing_translations!(master)
    raise ArgumentError, "not a master page" unless master.master?

    (@languages - [master.lang]).filter_map do |lang|
      next if master.version_for(lang)

      create_translation(master, lang)
    end
  end

  # Переводит текущее значение поля `field` у мастер-страницы на языки
  # всех УЖЕ существующих переводов и сохраняет его в каждом из них —
  # для случая "мастер отредактировали, нужно протащить только это поле
  # дальше", не трогая остальной контент переводов.
  def propagate_field!(master, field)
    raise ArgumentError, "not a master page" unless master.master?

    field = field.to_s
    raise ArgumentError, "#{field} is not translatable" unless Page::TRANSLATABLE_FIELDS.include?(field)

    source_text = master[field]
    return [] if source_text.blank?

    # я Claude (2026-08-11): не master.translations — Page#cascade_uri_to_
    # descendants (after_save, не связан с переводами) сам трогает
    # self.translations при любом сохранении страницы, где менялся uri,
    # и кеширует её пустой в момент создания. Если master — тот же
    # объект, что был только что создан/сохранён в этом же процессе,
    # ассоциация будет заведомо устаревшей. Прямой запрос это обходит.
    Page.where(master_id: master.id).map do |translation|
      translated = @gemini.translate(source_text, from: master.lang, to: translation.lang)
      translation.update!(field => translated)

      Result.new(lang: translation.lang, page: translation, error: nil)
    rescue => e
      Result.new(lang: translation.lang, page: translation, error: e.message)
    end
  end

  private

  def create_translation(master, lang)
    translation = build_translation(master, lang)

    texts = Page::TRANSLATABLE_FIELDS.index_with { |field| master[field] }.compact
    translated_texts = @gemini.translate_batch(texts, from: master.lang, to: lang)
    translated_texts.each { |field, value| translation[field] = value }

    translation.save!
    Result.new(lang: lang, page: translation, error: nil)
  rescue => e
    Result.new(lang: lang, page: nil, error: e.message)
  end

  def build_translation(master, lang)
    translation = master.dup

    translation.lang      = lang
    translation.master_id = master.id
    translation.published = false
    translation.edited_at = nil

    Page::MASTER_ONLY_FIELDS.each { |attr| translation[attr] = nil }

    translation.parent =
      master.parent.nil? ? nil : master.parent.translations.find_by(lang: lang)

    translation
  end
end
