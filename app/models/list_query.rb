# Резолвит conditions (произвольный Hash — не привязан к записи в БД)
# в реальную выборку объектов. Используется и Page#list_objects (у
# страницы conditions свои), и хелпером objects_matching в шаблонах
# (conditions собираются на лету, без страницы вообще).
#
# conditions:
#   {
#     "object"    => "Entity" | "Item" | "Event" | "Picture",
#     "tags"      => TagExpression AST (см. TagExpression), опционально
#     "schema"    => String | [String], name Schema (напр. "Hotel" или
#                    ["Restaurant", "CafeOrCoffeeShop"]), опционально —
#                    матчит и сам узел, и всех его потомков по иерархии
#                    (Hotel — потомок LodgingBusiness, "LodgingBusiness"
#                    заберёт и отели, и хостелы). Массив — это ИЛИ, не И:
#                    у объекта ровно один schema_id, "и Restaurant, и Cafe
#                    одновременно" не бывает физически; ancestry — дерево,
#                    а не DAG, так что поддеревья разных schema никогда
#                    не пересекаются — буквальный AND всегда дал бы пустоту.
#     "start_at"  => ISO8601 String, опционально — только для Event
#     "end_at"    => ISO8601 String, опционально — только для Event
#     "details"   => { "key" => "value" }, опционально — точное совпадение
#   }
class ListQuery
  # constantize, а не хэш констант — иначе при загрузке этого файла
  # (порядок require_all не гарантирован) может ещё не существовать
  # Entity/Item/Event/Picture.
  ALLOWED_OBJECT_TYPES = %w[Entity Item Event Picture].freeze

  def initialize(conditions)
    @conditions = conditions || {}
  end

  def objects
    object_type = @conditions["object"]
    raise ArgumentError, "unknown list object type: #{object_type.inspect}" unless ALLOWED_OBJECT_TYPES.include?(object_type)

    klass = object_type.constantize
    scope = klass.respond_to?(:active) ? klass.active : klass.all

    if @conditions["schema"].present?
      names = Array(@conditions["schema"])
      schema_ids = Schema.where(name: names).flat_map { |schema| schema.subtree.pluck(:id) }
      scope = schema_ids.any? ? scope.where(schema_id: schema_ids) : scope.none
    end

    if @conditions["start_at"].present? && klass.column_names.include?("start_at")
      scope = scope.where("start_at >= ?", @conditions["start_at"])
    end

    if @conditions["end_at"].present? && klass.column_names.include?("end_at")
      scope = scope.where("end_at <= ?", @conditions["end_at"])
    end

    if @conditions["tags"].present?
      ids = TagExpression.new(@conditions["tags"]).matching_ids(klass)
      scope = scope.where(id: ids.to_a)
    end

    # Публичные листинги (конструктор condition-страниц, objects_matching)
    # не должны показывать draft-объекты — только те, у кого есть
    # опубликованная detail-страница (Picture — не Pageable, пропускаем).
    # До details-фильтра ниже: тот через .select превращает scope в
    # обычный Array, на котором .where уже не сработает.
    if klass.include?(Pageable)
      published_ids = Page.where(pageable_type: object_type, published: true).select(:pageable_id)
      scope = scope.where(id: published_ids)
    end

    if @conditions["details"].present?
      scope = scope.select { |object| @conditions["details"].all? { |key, value| object.details.to_h[key].to_s == value.to_s } }
    end

    scope
  end

  # Массово считает list_objects.count для нескольких страниц ОДНИМ
  # набором запросов на группу вместо одного queries-per-page — раньше
  # _page_link_with_count дёргал page.list_objects.count на КАЖДУЮ
  # ссылку-сиблинг по отдельности (полный TagExpression + published-
  # подзапрос), и даже на маленькой /philippines это давало 400+ SQL-
  # запросов и несколько секунд рендера (см. обсуждение производительности).
  #
  # Работает для двух реальных форм conditions["tags"] у сгенерированных
  # List-страниц (TemplateFieldRenderer всегда кладёт туда slug, не
  # ручной AST с or/not) — простая строка (top-level List) и ["and",
  # parent_slug, own_slug] (вложенный List, см.
  # PageTemplateGenerator#conditions_hash/#combine_tags). Всё, что не
  # подходит под эти формы — поштучно через обычный #objects.count
  # (медленнее, но корректно; на сгенерированных страницах не встречается).
  #
  # pages — Array/Relation Page. Возвращает {page.id => count}.
  def self.batch_counts_for(pages)
    pages = pages.to_a
    result = {}

    pages.group_by { |p| [p.effective_conditions["object"], Array(p.effective_conditions["schema"])] }.each do |(object_type, schema_names), group_pages|
      unless object_type && ALLOWED_OBJECT_TYPES.include?(object_type)
        group_pages.each { |p| result[p.id] = 0 }
        next
      end

      klass = object_type.constantize
      base = klass.respond_to?(:active) ? klass.active : klass.all

      if schema_names.present?
        schema_ids = Schema.where(name: schema_names).flat_map { |schema| schema.subtree.pluck(:id) }
        base = schema_ids.any? ? base.where(schema_id: schema_ids) : base.none
      end

      if klass.include?(Pageable)
        published_ids = Page.where(pageable_type: object_type, published: true).select(:pageable_id)
        base = base.where(id: published_ids)
      end

      eligible_ids = base.select(:id)

      # Пустая строка/nil в tags — как и в ListQuery#objects (см. выше,
      # .present? false пропускает фильтр целиком) — значит "без фильтра
      # по тегам", а не "тег с пустым slug"; встречается у страниц,
      # заведённых руками без явных conditions (например /yoga-styles/*
      # — см. обсуждение производительности). Считаем один раз на группу,
      # а не отдельным tag_counts-запросом с пустым label.
      blank_tags, simple, nested, other = [], [], [], []
      group_pages.each do |p|
        tags = p.effective_conditions["tags"]
        if tags.is_a?(String) && tags.blank?
          blank_tags << p
        elsif tags.is_a?(String)
          simple << p
        elsif tags.is_a?(Array) && tags.size == 3 && tags[0] == "and" && tags[1].is_a?(String) && tags[2].is_a?(String)
          nested << p
        else
          other << p
        end
      end

      if blank_tags.any?
        count = eligible_ids.count
        blank_tags.each { |p| result[p.id] = count }
      end

      if simple.any?
        labels = simple.map { |p| p.effective_conditions["tags"] }.uniq
        counts = tag_counts(object_type, labels, eligible_ids)
        simple.each { |p| result[p.id] = counts[p.effective_conditions["tags"]] || 0 }
      end

      nested.group_by { |p| p.effective_conditions["tags"][1] }.each do |parent_label, siblings|
        parent_id = resolve_tag_id(parent_label)
        if parent_id.nil?
          siblings.each { |p| result[p.id] = 0 }
          next
        end

        scoped_ids = Tagging.where(taggable_type: object_type, tag_id: parent_id, taggable_id: eligible_ids).select(:taggable_id)
        labels = siblings.map { |p| p.effective_conditions["tags"][2] }.uniq
        counts = tag_counts(object_type, labels, scoped_ids)
        siblings.each { |p| result[p.id] = counts[p.effective_conditions["tags"][2]] || 0 }
      end

      other.each { |p| result[p.id] = new(p.effective_conditions).objects.count }
    end

    result
  end

  def self.resolve_tag_id(label)
    Tag.find_by(slug: label)&.id || Tag.find_by(name: label)&.id
  end
  private_class_method :resolve_tag_id

  # label (slug, с фолбэком на name — как и TagExpression#tag_ids) -> id,
  # для нескольких labels сразу, без по-одному find_by в цикле.
  def self.tag_counts(object_type, labels, scope_ids)
    return {} if labels.empty?

    by_slug = Tag.where(slug: labels).pluck(:slug, :id).to_h
    missing = labels - by_slug.keys
    by_name = missing.any? ? Tag.where(name: missing).pluck(:name, :id).to_h : {}

    tag_id_by_label = labels.index_with { |label| by_slug[label] || by_name[label] }
    ids = tag_id_by_label.values.compact
    counts_by_tag_id = ids.any? ? Tagging.where(taggable_type: object_type, tag_id: ids, taggable_id: scope_ids).group(:tag_id).count : {}

    tag_id_by_label.transform_values { |tag_id| tag_id ? (counts_by_tag_id[tag_id] || 0) : 0 }
  end
  private_class_method :tag_counts
end
