require 'json'
require 'uri'

# Импорт уточнений по Entity из JSON (админка: /admin/import/entities).
#
# Файл — массив объектов, по одному на entity:
#
#   [{
#     "entity_id": 1,              # есть и найден -> правка; null/нет ключа -> создание (нужны name и schema)
#     "name": "...", "short": "...", "schema": "Beach",   # schema — по имени
#     "address": "...", "latitude": 45.6, "longitude": 13.7,
#     "plus_code": "...", "parent_id": 5, "is_closed": false, "generate_pages": true,
#     "details":  { "beach_length": 200, "email": "a@b.it", "old_label": null },  # имя label -> значение; null = удалить
#     "links":    { "facebook": "https://...", "webcam": ["https://a", "https://b"], "youtube": null },
#     "profiles": ["https://www.facebook.com/x", "https://www.tripadvisor.com/..."],  # site по домену url
#     "tags":        ["public shower", "childFriendly"],   # только добавляются
#     "tags_remove": ["paid entrance"]                      # только удаляются
#   }]
#
# Правила:
#   - ключа нет -> поле не трогаем; значение null -> удаляем detail / link (для скалярных полей — обнуляем);
#   - неизвестный ключ верхнего уровня — ошибка записи (строго, в dry-run тоже);
#   - неизвестный label / тег / домен профиля — предупреждение, элемент пропускается;
#   - links: значение (строка или массив) — полный набор url для label: лишние удаляются, недостающие создаются
#     (если был один и стал один — url меняется на месте);
#   - создание с name+schema, уже существующими у другой entity, — ошибка (возможный дубль, укажи entity_id);
#   - запись с ошибкой откатывается целиком (savepoint), остальные применяются.
#
#   report = EntityImporter.new(json_string).call(apply: false)   # dry-run: всё откатывается
#   report = EntityImporter.new(json_string).call(apply: true)    # одна транзакция
class EntityImporter
  SCALAR_KEYS = %w[name short address latitude longitude plus_code is_closed generate_pages].freeze
  KEYS = (SCALAR_KEYS + %w[entity_id schema parent_id details links profiles tags tags_remove]).freeze
  IGNORED_ENTITY_CHANGES = %w[id created_at updated_at].freeze
  NONE = '∅'.freeze

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

    load_lookups
    records = []
    @google_profiles = []

    # requires_new: Rollback в dry-run должен откатывать и когда импорт вызван внутри чужой транзакции
    ActiveRecord::Base.transaction(requires_new: true) do
      records = data.each_with_index.map { |item, i| process(item, i + 1) }
      raise ActiveRecord::Rollback unless apply
    end

    resolve_google_redirects if apply

    Report.new(records: records, fatal: nil, applied: apply)
  end

  private

  def parse
    data = JSON.parse(@json.to_s)
    unless data.is_a?(Array)
      @fatal = 'Файл должен содержать JSON-массив объектов (по одному на entity)'
      return nil
    end
    data
  rescue JSON::ParserError => e
    @fatal = "Некорректный JSON: #{e.message.lines.first.to_s.strip}"
    nil
  end

  def load_lookups
    @labels  = Label.all.index_by(&:name)
    @schemas = Schema.all.index_by(&:name)
    @sites   = Site.all.index_by { |s| s.domain.to_s.downcase }
    @tags_by_name  = Tag.all.index_by(&:name)
    @tags_by_lower = Tag.all.group_by { |t| t.name.to_s.downcase.strip }
  end

  # ---- одна запись ---------------------------------------------------------

  def process(item, index)
    rec = { index: index, entity_id: nil, name: nil, action: :unchanged, changes: [], warnings: [], errors: [] }

    unless item.is_a?(Hash)
      rec[:errors] << 'элемент массива должен быть объектом'
      rec[:action] = :error
      return rec
    end

    rec[:name] = item['name']
    unknown = item.keys - KEYS
    rec[:errors] << "неизвестные ключи: #{unknown.join(', ')}" if unknown.any?

    if rec[:errors].empty?
      begin
        ActiveRecord::Base.transaction(requires_new: true) do
          process_entity(item, rec)
          raise ActiveRecord::Rollback if rec[:errors].any?
        end
      rescue StandardError => e
        rec[:errors] << "#{e.class}: #{e.message}"
      end
    end

    if rec[:errors].any?
      rec[:action] = :error
      rec[:changes] = []
    elsif rec[:action] != :create
      rec[:action] = rec[:changes].any? ? :update : :unchanged
    end
    rec
  end

  def process_entity(item, rec)
    entity = resolve_entity(item, rec)
    return if rec[:errors].any?

    rec[:entity_id] = entity.id
    attrs = scalar_attributes(item, rec)
    attrs.merge!(schema_attributes(item, rec, entity))
    attrs.merge!(parent_attributes(item, rec))
    return if rec[:errors].any?

    entity.assign_attributes(attrs)
    record_entity_changes(entity, rec)
    entity.save!
    rec[:entity_id] = entity.id

    apply_details(entity, item['details'], rec) if item.key?('details')
    apply_links(entity, item['links'], rec)     if item.key?('links')
    apply_profiles(entity, item['profiles'], rec) if item.key?('profiles')
    apply_tags(entity, item['tags'], item['tags_remove'], rec) if item.key?('tags') || item.key?('tags_remove')
  end

  def resolve_entity(item, rec)
    id = item['entity_id']

    if id.nil?
      create_entity_checked(item, rec)
    elsif !id.is_a?(Integer)
      rec[:errors] << 'entity_id должен быть целым числом или null'
      nil
    else
      entity = Entity.find_by(id: id)
      rec[:errors] << "entity_id #{id} не найден (для создания поставь null)" unless entity
      rec[:name] ||= entity&.name
      entity
    end
  end

  def create_entity_checked(item, rec)
    name = item['name']
    schema_name = item['schema']
    rec[:errors] << 'для создания нужен name' unless name.is_a?(String) && name.strip.present?
    rec[:errors] << 'для создания нужен schema' unless schema_name.is_a?(String) && schema_name.strip.present?
    return nil if rec[:errors].any?

    schema = @schemas[schema_name]
    unless schema
      rec[:errors] << "schema '#{schema_name}' не найдена"
      return nil
    end

    dup = Entity.find_by(name: name.strip, schema_id: schema.id)
    if dup
      rec[:errors] << "возможный дубль: entity ##{dup.id} уже имеет name '#{name.strip}' и schema '#{schema_name}' (укажи entity_id)"
      return nil
    end

    rec[:action] = :create
    Entity.new
  end

  # ---- поля entity ---------------------------------------------------------

  def scalar_attributes(item, rec)
    attrs = {}
    SCALAR_KEYS.each do |key|
      next unless item.key?(key)

      value = item[key]
      case key
      when 'name'
        if value.is_a?(String) && value.strip.present? then attrs[key] = value.strip
        else rec[:errors] << 'name не может быть пустым' end
      when 'short', 'address', 'plus_code'
        if value.nil? || value.is_a?(String) then attrs[key] = value&.strip.presence
        else rec[:errors] << "#{key} должен быть строкой или null" end
      when 'latitude', 'longitude'
        limit = key == 'latitude' ? 90 : 180
        if value.nil? then attrs[key] = nil
        elsif value.is_a?(Numeric) && value.abs <= limit then attrs[key] = value.to_f
        else rec[:errors] << "#{key} должен быть числом в диапазоне ±#{limit}" end
      when 'is_closed', 'generate_pages'
        if [true, false].include?(value) then attrs[key] = value
        else rec[:errors] << "#{key} должен быть true или false" end
      end
    end
    attrs
  end

  def schema_attributes(item, rec, _entity)
    return {} unless item.key?('schema')

    name = item['schema']
    schema = name.is_a?(String) ? @schemas[name] : nil
    unless schema
      rec[:errors] << "schema '#{name}' не найдена"
      return {}
    end
    { 'schema_id' => schema.id }
  end

  def parent_attributes(item, rec)
    return {} unless item.key?('parent_id')

    pid = item['parent_id']
    return { 'parent_id' => nil } if pid.nil?

    if pid.is_a?(Integer) && Entity.exists?(pid)
      { 'parent_id' => pid }
    else
      rec[:errors] << "parent_id #{pid.inspect} не найден"
      {}
    end
  end

  def record_entity_changes(entity, rec)
    entity.changes.each do |field, (from, to)|
      next if IGNORED_ENTITY_CHANGES.include?(field)

      if field == 'schema_id'
        from = Schema.find_by(id: from)&.name
        to   = Schema.find_by(id: to)&.name
        field = 'schema'
      end
      add_change(rec, field, from, to)
    end
  end

  # ---- details -------------------------------------------------------------

  def apply_details(entity, details, rec)
    unless details.is_a?(Hash)
      rec[:errors] << 'details должен быть объектом {label: значение}'
      return
    end

    effective_ids = nil

    details.each do |label_name, value|
      label = @labels[label_name]
      unless label
        rec[:warnings] << "details: неизвестный label '#{label_name}' — пропущен"
        next
      end

      effective_ids ||= entity.effective_labels.pluck(:id)
      rec[:warnings] << "details: label '#{label_name}' не входит в labels схемы этой entity (записан всё равно)" unless effective_ids.include?(label.id)

      detail = entity.detail_records.find_by(label_id: label.id)
      field  = "details.#{label_name}"

      if value.nil?
        if detail
          add_change(rec, field, detail.value, '(удалён)')
          detail.destroy!
        end
        next
      end

      new_value = detail_value(value, label, rec, field)
      next unless new_value

      if detail
        next if same_detail_value?(detail.value, new_value, label)

        add_change(rec, field, detail.value, new_value)
        detail.update!(value: new_value)
      else
        add_change(rec, field, nil, new_value)
        entity.detail_records.create!(label: label, value: new_value)
      end
    end
  end

  def detail_value(value, label, rec, field)
    unless value.is_a?(String) || value.is_a?(Numeric) || [true, false].include?(value)
      rec[:errors] << "#{field}: значение должно быть строкой, числом или boolean"
      return nil
    end

    text = value.to_s
    if text.strip.empty?
      rec[:errors] << "#{field}: пустая строка (для удаления используй null)"
      return nil
    end

    if label.field_type == 'float' && Float(text, exception: false).nil?
      rec[:errors] << "#{field}: '#{text}' — не число (label типа float)"
      return nil
    end

    text
  end

  def same_detail_value?(old_value, new_value, label)
    return old_value == new_value unless label.field_type == 'float'

    Float(old_value.to_s, exception: false) == Float(new_value, exception: false)
  end

  # ---- links ---------------------------------------------------------------

  def apply_links(entity, links, rec)
    unless links.is_a?(Hash)
      rec[:errors] << 'links должен быть объектом {label: url | [url, ...] | null}'
      return
    end

    links.each do |label_name, value|
      label = @labels[label_name]
      unless label
        rec[:warnings] << "links: неизвестный label '#{label_name}' — пропущен"
        next
      end

      field    = "links.#{label_name}"
      existing = entity.links.where(label_id: label.id).order(:id).to_a

      if value.nil?
        existing.each do |link|
          add_change(rec, field, link.url, '(удалена)')
          link.destroy!
        end
        next
      end

      desired = normalize_urls(Array(value), rec, field)
      next if rec[:errors].any?

      if existing.size == 1 && desired.size == 1
        link = existing.first
        next if link.url == desired.first

        add_change(rec, field, link.url, desired.first)
        link.update!(url: desired.first, checked_at: nil, response: nil, redirected: false, redirected_to: nil)
      else
        existing.reject { |l| desired.include?(l.url) }.each do |link|
          add_change(rec, field, link.url, '(удалена)')
          link.destroy!
        end
        (desired - existing.map(&:url)).each do |url|
          add_change(rec, field, nil, url)
          entity.links.create!(label: label, url: url)
        end
      end
    end
  end

  def normalize_urls(values, rec, field)
    values.filter_map do |u|
      url = u.is_a?(String) ? u.strip : nil
      if url && valid_url?(url)
        url
      else
        rec[:errors] << "#{field}: некорректный url #{u.inspect}"
        nil
      end
    end.uniq
  end

  def valid_url?(url)
    url.match?(%r{\Ahttps?://[^\s]+\z}i) && !URI.parse(url).host.to_s.empty?
  rescue URI::InvalidURIError
    false
  end

  # ---- profiles ------------------------------------------------------------

  def apply_profiles(entity, urls, rec)
    unless urls.is_a?(Array)
      rec[:errors] << 'profiles должен быть массивом url'
      return
    end

    normalize_urls(urls, rec, 'profiles').each do |url|
      site = site_for(URI.parse(url).host)
      unless site
        rec[:warnings] << "profiles: для домена #{URI.parse(url).host} нет site — #{url} пропущен"
        next
      end
      next if entity.profiles.exists?(url: url)

      now = Time.current
      # insert!, а не save!: у Profile after_save ходит в сеть (google maps redirect),
      # в dry-run этого быть не должно — для применения резолвим после коммита.
      Profile.insert!({ site_id: site.id, url: url, profileable_type: 'Entity', profileable_id: entity.id,
                        alive: true, created_at: now, updated_at: now })
      add_change(rec, "profiles.#{site.domain}", nil, url)
      @google_profiles << [entity.id, url] if site.domain.to_s.downcase == 'google.com'
    end
  end

  # a.b.example.com -> a.b.example.com, b.example.com, example.com (до двух меток)
  def site_for(host)
    labels = host.to_s.downcase.split('.')
    while labels.size >= 2
      site = @sites[labels.join('.')]
      return site if site
      labels.shift
    end
    nil
  end

  def resolve_google_redirects
    @google_profiles.each do |entity_id, url|
      profile = Profile.find_by(profileable_type: 'Entity', profileable_id: entity_id, url: url)
      next unless profile

      final_url = RedirectResolver.resolve_final_url(url)
      profile.update_columns(redirected: true, redirected_to: final_url) if final_url && final_url != url
    rescue StandardError
      next
    end
  end

  # ---- tags ----------------------------------------------------------------

  def apply_tags(entity, add_names, remove_names, rec)
    add_names    ||= []
    remove_names ||= []

    [['tags', add_names], ['tags_remove', remove_names]].each do |key, names|
      unless names.is_a?(Array) && names.all? { |n| n.is_a?(String) }
        rec[:errors] << "#{key} должен быть массивом строк"
        return
      end
    end

    to_add    = resolve_tags(add_names, rec, 'tags')
    to_remove = resolve_tags(remove_names, rec, 'tags_remove')

    both = to_add & to_remove
    if both.any?
      rec[:errors] << "теги одновременно в tags и tags_remove: #{both.map(&:name).join(', ')}"
      return
    end

    to_add.each do |tag|
      next if entity.taggings.exists?(tag_id: tag.id)

      entity.taggings.create!(tag: tag)
      add_change(rec, 'tags', nil, tag.name)
    end

    to_remove.each do |tag|
      tagging = entity.taggings.find_by(tag_id: tag.id)
      next unless tagging

      tagging.destroy!
      add_change(rec, 'tags', tag.name, '(снят)')
    end
  end

  # точное имя; иначе совпадение без учёта регистра, если оно однозначно
  def resolve_tags(names, rec, key)
    names.filter_map do |raw|
      name = raw.strip
      next @tags_by_name[name] if @tags_by_name[name]

      candidates = @tags_by_lower[name.downcase] || []
      case candidates.size
      when 1 then candidates.first
      when 0
        rec[:warnings] << "#{key}: неизвестный тег '#{name}' — пропущен"
        nil
      else
        rec[:warnings] << "#{key}: тег '#{name}' неоднозначен (#{candidates.map(&:name).join(' | ')}) — пропущен"
        nil
      end
    end.uniq
  end

  # ---- общее ---------------------------------------------------------------

  def add_change(rec, field, from, to)
    rec[:changes] << { field: field, from: from.nil? ? NONE : from, to: to.nil? ? NONE : to }
  end
end
