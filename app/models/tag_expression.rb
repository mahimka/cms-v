# Вычисляет вложенное булево AST над тегами (по slug — а если такого
# slug нет, пробуем как name, для обратной совместимости со старыми
# conditions/embedded filter, написанными руками по имени) в множество
# id объектов.
#
# Узел — либо строка (slug или, по-старому, name тега), либо массив
# [оператор, операнд, операнд, ...]:
#
#   "hotel"                                     -> все объекты с тегом hotel
#   ["hotel", "izola"]                          -> hotel И izola (оператор не указан — неявный and)
#   ["and", "hotel", "izola"]                   -> то же самое явно
#   ["or", "hotel", "hostel"]                   -> hotel ИЛИ hostel
#   ["and", ["or", "hotel", "hostel"], "izola"] -> (hotel ИЛИ hostel) И izola
#   ["not", ["and", "ankaran", "koper"], "kamenit"]
#     -> (ankaran И koper) БЕЗ "kamenit" — not бинарный: левое минус правое
class TagExpression
  OPERATORS = %w[and or not].freeze

  def initialize(node)
    @node = node
  end

  def matching_ids(klass)
    evaluate(@node, klass)
  end

  private

  def evaluate(node, klass)
    return tag_ids(node, klass) if node.is_a?(String)

    if node.first.is_a?(String) && OPERATORS.include?(node.first)
      op, *operands = node
    else
      # ["Hotel", "Izola"] без оператора — самая частая ручная ошибка
      # при заполнении JSON, трактуем как and списком тегов.
      op, operands = "and", node
    end

    sets = operands.map { |operand| evaluate(operand, klass) }

    case op
    when "and" then sets.reduce(:&) || Set.new
    when "or"  then sets.reduce(:|) || Set.new
    when "not"
      raise ArgumentError, "'not' takes exactly 2 operands (left, right)" unless sets.size == 2

      sets[0] - sets[1]
    end
  end

  # slug — основной способ адресовать тег; name — фолбэк ради старых
  # conditions/embedded filter (см. _compare_beaches_rows.erb и т.п.),
  # написанных руками по имени ещё до того, как slug стал обязательным.
  def tag_ids(identifier, klass)
    Set.new(klass.joins(:tags).where(tags: { slug: identifier }).or(klass.joins(:tags).where(tags: { name: identifier })).pluck(:id))
  end
end
