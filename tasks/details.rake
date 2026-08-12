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
end
