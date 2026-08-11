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
  # Page требует, чтобы родитель перевода сам был переводом родителя
  # мастера (см. Page#translation_parent_must_match_master_parent) —
  # поэтому для глубоко вложенной страницы (/izola/beaches/delfincek)
  # сначала рекурсивно досоздаёт недостающие переводы всех предков на
  # тот же язык, и только потом — перевод самой страницы. Если перевод
  # какого-то предка не удался — перевод потомка не пытаемся создать,
  # он всё равно провалит ту же validation.
  def create_missing_translations!(master)
    raise ArgumentError, "not a master page" unless master.master?

    (@languages - [master.lang]).flat_map do |lang|
      master.version_for(lang) ? [] : ensure_translated(master, lang)
    end
  end

  # Переводит текущее значение поля `field` у мастер-страницы на языки
  # всех УЖЕ существующих переводов и сохраняет его в каждом из них —
  # для случая "мастер отредактировали, нужно протащить только это поле
  # дальше", не трогая остальной контент переводов.
  def propagate_field!(master, field)
    raise ArgumentError, "not a master page" unless master.master?

    field = validate_translatable_field!(field)
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

  # Переводит поле `field` мастер-страницы этого перевода и сохраняет
  # результат ТОЛЬКО в самом translation — не трогает другие языковые
  # версии. Для случая "открыл конкретный перевод, хочу перетянуть/
  # обновить в нём одно поле из мастера".
  def translate_field_from_master!(translation, field)
    raise ArgumentError, "not a translation" unless translation.translation?

    field = validate_translatable_field!(field)
    master = translation.master
    source_text = master[field]

    return Result.new(lang: translation.lang, page: translation, error: nil) if source_text.blank?

    # begin/rescue тут, а не method-level — иначе он ловит и свои же
    # ArgumentError-проверки выше, превращая программистскую ошибку в
    # тихий "неуспешный" Result вместо настоящего исключения.
    begin
      translated = @gemini.translate(source_text, from: master.lang, to: translation.lang)
      translation.update!(field => translated)

      Result.new(lang: translation.lang, page: translation, error: nil)
    rescue => e
      Result.new(lang: translation.lang, page: translation, error: e.message)
    end
  end

  private

  def validate_translatable_field!(field)
    field = field.to_s
    raise ArgumentError, "#{field} is not translatable" unless Page::TRANSLATABLE_FIELDS.include?(field)

    field
  end

  # Возвращает плоский массив Result — переводы всех предков, которых
  # не хватало (в порядке от корня вниз), плюс перевод самой page, если
  # до него дошло. Пуст, если перевод для lang уже существует.
  def ensure_translated(page, lang)
    existing = page.version_for(lang)
    return [] if existing

    ancestor_results = page.parent ? ensure_translated(page.parent, lang) : []
    return ancestor_results if ancestor_results.any? { |r| !r.success? }

    ancestor_results + [create_translation(page, lang)]
  end

  def create_translation(master, lang)
    translation = build_translation(master, lang)

    texts = Page::TRANSLATABLE_FIELDS.index_with { |field| master[field] }.reject { |_, value| value.blank? }
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

    # version_for, не master.parent.translations — см. комментарий в
    # propagate_field! про устаревающий кэш has_many :translations.
    translation.parent =
      master.parent.nil? ? nil : master.parent.version_for(lang)

    translation
  end
end
