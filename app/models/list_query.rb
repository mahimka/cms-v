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

    if @conditions["details"].present?
      scope = scope.select { |object| @conditions["details"].all? { |key, value| object.details.to_h[key].to_s == value.to_s } }
    end

    scope
  end
end
