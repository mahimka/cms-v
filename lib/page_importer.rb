require 'json'

# Первичное заполнение текстов страниц из JSON (админка: /admin/import/pages).
#
# Файл — массив объектов, по одному на страницу:
#
#   [{
#     "id": 12,                    # обязателен; страницы только правятся, не создаются
#     "slug": "...", "uri": "...", # только для справки: сверяются со страницей, не меняются
#     "title": "...", "h1": "...", "subtitle": "...",
#     "anchor_1": "...", "anchor_2": "...", "anchor_3": "...",
#     "meta_description": "...", "body": "...", "faq": "...",
#     "robots_index": true, "robots_follow": true   # <meta name="robots">: index/noindex, follow/nofollow
#   }]
#
# Правила:
#   - ключа нет -> поле не трогаем; null или "" -> поле очищается;
#   - slug / uri не применяются; несовпадение со страницей — предупреждение (id не тот?);
#   - страница создана по шаблону (template_id) -> изменённые поля помечаются как правленные вручную
#     (edited_columns), чтобы перегенерация их не затёрла;
#   - неизвестный ключ верхнего уровня — ошибка записи (строго, в dry-run тоже);
#   - запись с ошибкой откатывается целиком (savepoint), остальные применяются.
#
#   report = PageImporter.new(json_string).call(apply: false)   # dry-run: всё откатывается
#   report = PageImporter.new(json_string).call(apply: true)    # одна транзакция
class PageImporter
  FIELDS     = %w[title h1 subtitle anchor_1 anchor_2 anchor_3 meta_description body faq].freeze
  REFERENCE  = %w[slug uri].freeze
  FLAGS      = %w[robots_index robots_follow].freeze  # true/false; ключа нет -> не трогаем
  KEYS       = (%w[id] + REFERENCE + FIELDS + FLAGS).freeze
  NONE       = '∅'.freeze

  Report = Struct.new(:records, :fatal, :applied, keyword_init: true) do
    def counts
      records.group_by { |r| r[:action] }.transform_values(&:size)
    end

    def ok?
      fatal.nil?
    end
  end

  def initialize(json)
    @json = json
  end

  def call(apply: false)
    data = parse
    return Report.new(records: [], fatal: @fatal, applied: false) unless data

    records = []
    # requires_new: Rollback в dry-run должен откатывать и когда импорт вызван внутри чужой транзакции
    ActiveRecord::Base.transaction(requires_new: true) do
      records = data.each_with_index.map { |item, i| process(item, i + 1) }
      raise ActiveRecord::Rollback unless apply
    end

    Report.new(records: records, fatal: nil, applied: apply)
  end

  private

  def parse
    data = JSON.parse(@json.to_s)
    unless data.is_a?(Array)
      @fatal = 'Файл должен содержать JSON-массив объектов (по одному на страницу)'
      return nil
    end
    data
  rescue JSON::ParserError => e
    @fatal = "Некорректный JSON: #{e.message.lines.first.to_s.strip}"
    nil
  end

  def process(item, index)
    rec = { index: index, page_id: nil, name: nil, action: :unchanged, changes: [], warnings: [], errors: [] }

    unless item.is_a?(Hash)
      rec[:errors] << 'элемент массива должен быть объектом'
      rec[:action] = :error
      return rec
    end

    rec[:name] = item['h1'] || item['title'] || item['uri']
    unknown = item.keys - KEYS
    rec[:errors] << "неизвестные ключи: #{unknown.join(', ')}" if unknown.any?

    if rec[:errors].empty?
      begin
        ActiveRecord::Base.transaction(requires_new: true) do
          process_page(item, rec)
          raise ActiveRecord::Rollback if rec[:errors].any?
        end
      rescue StandardError => e
        rec[:errors] << "#{e.class}: #{e.message}"
      end
    end

    if rec[:errors].any?
      rec[:action] = :error
      rec[:changes] = []
    else
      rec[:action] = rec[:changes].any? ? :update : :unchanged
    end
    rec
  end

  def process_page(item, rec)
    id = item['id']
    unless id.is_a?(Integer)
      rec[:errors] << 'id обязателен и должен быть целым числом'
      return
    end

    page = Page.find_by(id: id)
    unless page
      rec[:errors] << "страница id #{id} не найдена"
      return
    end

    rec[:page_id] = id
    rec[:name] ||= page.h1
    check_reference(item, page, rec)

    attrs = field_attributes(item, rec)
    return if rec[:errors].any?

    page.assign_attributes(attrs)
    changed = page.changes.keys & (FIELDS + FLAGS)
    page.changes.slice(*changed).each { |field, (from, to)| add_change(rec, field, from, to) }
    return if changed.empty?

    page.save!
    # страница по шаблону: ручной ввод защищаем от перегенерации (как PagesController#patch)
    page.mark_edited_fields!(changed) if page.template_id.present?
  end

  def check_reference(item, page, rec)
    REFERENCE.each do |key|
      next unless item.key?(key)

      expected = page.public_send(key).to_s
      given    = item[key].to_s
      rec[:warnings] << "#{key}: в файле '#{given}', на странице '#{expected}' (не меняется) — тот ли id?" if given != expected
    end
  end

  def field_attributes(item, rec)
    FLAGS.each do |key|
      rec[:errors] << "#{key} должен быть true или false" if item.key?(key) && ![true, false].include?(item[key])
    end

    flags = FLAGS.select { |key| item.key?(key) && [true, false].include?(item[key]) }.to_h { |key| [key, item[key]] }

    FIELDS.each_with_object(flags) do |key, attrs|
      next unless item.key?(key)

      value = item[key]
      if value.nil? || value.is_a?(String)
        attrs[key] = value&.strip.presence
      else
        rec[:errors] << "#{key} должен быть строкой или null"
      end
    end
  end

  def add_change(rec, field, from, to)
    rec[:changes] << { field: field, from: from.nil? ? NONE : from, to: to.nil? ? NONE : to }
  end
end
