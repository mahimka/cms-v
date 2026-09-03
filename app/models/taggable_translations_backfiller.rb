# Массовое заполнение .translations (JSON locale => строка) у моделей
# с паттерном перевода как у Tag/Label (см. #translation(lang) в них
# самих). В отличие от PageTranslator — тут нет отдельной записи на
# язык, один record хранит все переводы в одном hash-столбце, поэтому
# единица работы — не "страница", а "недостающий язык у записи".
#
# Никогда не перезаписывает уже заполненные вручную translations[lang] —
# только доливает то, чего не хватает.
#
# source language — всегда "en": name у Tag/Label заведён по-английски
# (в отличие от Page, где settings.home_language — основной язык сайта).
# Раньше сюда передавался home_language и он же исключался из целей —
# из-за этого sl-перевод никогда не генерировался (см. /admin/labels/1082).
class TaggableTranslationsBackfiller
  BATCH_SIZE = 25
  SOURCE_LANGUAGE = 'en'.freeze

  def initialize(gemini_client:, languages:)
    @gemini = gemini_client
    @languages = languages.map(&:to_s) - [SOURCE_LANGUAGE]
  end

  # klass — Tag или Label (любая модель со столбцом translations и полем
  # name). Возвращает { lang => { record_id => true/false } } — для
  # отчёта в rake-таске.
  def backfill!(klass)
    report = Hash.new { |h, k| h[k] = {} }

    @languages.each do |lang|
      missing = klass.find_each.to_a.select { |record| record.translations&.dig(lang).blank? }

      missing.each_slice(BATCH_SIZE) do |batch|
        report[lang].merge!(translate_batch(batch, lang))
      end
    end

    report
  end

  private

  def translate_batch(records, lang)
    # Если translations['en'] уже заполнен вручную человеческим текстом —
    # переводим его, а не сырой (иногда technical snake_case) name.
    texts = records.each_with_object({}) do |record, h|
      h[record.id.to_s] = record.translations&.dig('en').presence || record.name
    end
    translated = @gemini.translate_batch(texts, from: SOURCE_LANGUAGE, to: lang)

    records.each_with_object({}) do |record, result|
      value = translated[record.id.to_s]

      result[record.id] =
        if value.present?
          record.update(translations: (record.translations || {}).merge(lang => value))
        else
          false
        end
    end
  end
end
