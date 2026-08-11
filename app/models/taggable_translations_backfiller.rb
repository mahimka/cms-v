# Массовое заполнение .translations (JSON locale => строка) у моделей
# с паттерном перевода как у Tag/Label (см. #translation(lang) в них
# самих). В отличие от PageTranslator — тут нет отдельной записи на
# язык, один record хранит все переводы в одном hash-столбце, поэтому
# единица работы — не "страница", а "недостающий язык у записи".
#
# Никогда не перезаписывает уже заполненные вручную translations[lang] —
# только доливает то, чего не хватает.
class TaggableTranslationsBackfiller
  BATCH_SIZE = 25

  def initialize(gemini_client:, languages:, home_language:)
    @gemini = gemini_client
    @languages = languages.map(&:to_s) - [home_language.to_s]
    @home_language = home_language.to_s
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
    texts = records.each_with_object({}) { |record, h| h[record.id.to_s] = record.name }
    translated = @gemini.translate_batch(texts, from: @home_language, to: lang)

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
