namespace :details do
  desc "Переносит записи из старой колонки details (JSON-хэш) Entity/Item/Event в таблицу details (Detail)"
  task :backfill do
    unresolved = Hash.new(0)

    [Entity, Item, Event].each do |klass|
      klass.find_each do |record|
        # read_attribute в обход текущего метода details — на момент
        # деплоя этот rake обычно накатывается вместе с изменениями в
        # моделях (serialize :details, JSON уже убран), так что колонка
        # читается как сырая строка. Hash-ветка — на случай, если задачу
        # всё же запустят до этих изменений в модели.
        raw_value = record.read_attribute(:details)
        raw = case raw_value
              when Hash   then raw_value
              when String then (JSON.parse(raw_value.presence || "{}") rescue {})
              else {}
              end

        raw.each do |key, value|
          next if key.blank?

          label = Label.find_by(name: key)

          unless label
            unresolved[key] += 1
            next
          end

          Detail.find_or_create_by!(detailable: record, label: label) do |detail|
            detail.value = value
          end
        end
      end
    end

    puts "Неразрешённые ключи (нет подходящего Label — разобрать вручную):"
    unresolved.sort_by { |_, count| -count }.each do |key, count|
      puts "  #{key.inspect} (#{count}x)"
    end
  end

  JUNK_VALUES = ["replace me", "edit me!", "", nil].freeze

  # Лейблы, выведенные из оборота как ключи details — либо перенесены в
  # обычные колонки (latitude/longitude -> entities.latitude/longitude),
  # либо больше не актуальны (high_60/low_60).
  OBSOLETE_LABELS = %w[latitude longitude high_60 low_60].freeze

  desc "Удаляет details с устаревшими label (#{OBSOLETE_LABELS.join(', ')}) и details с мусорными/пустыми value"
  task :cleanup_junk do
    # delete_all не поддерживает joins — удаляем по подзапросу id.
    obsolete = Detail.where(id: Detail.joins(:label).where(labels: { name: OBSOLETE_LABELS }).select(:id))
    obsolete_count = obsolete.count
    obsolete.delete_all

    junk_values = Detail.where(value: JUNK_VALUES)
    junk_values_count = junk_values.count
    junk_values.delete_all

    # На случай пробельных "пустых" значений, не пойманных точным списком выше.
    blank_ish = Detail.select { |d| d.value.to_s.strip.empty? }
    blank_ish_count = blank_ish.size
    Detail.where(id: blank_ish.map(&:id)).delete_all if blank_ish_count.positive?

    puts "Удалено с устаревшим label (#{OBSOLETE_LABELS.join(', ')}): #{obsolete_count}"
    puts "Удалено с мусорным value (#{JUNK_VALUES.map(&:inspect).join(', ')}): #{junk_values_count}"
    puts "Удалено дополнительно blank-после-strip: #{blank_ish_count}"
    puts "Осталось details: #{Detail.count}"
  end
end
