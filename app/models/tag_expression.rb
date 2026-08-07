# Вычисляет вложенное булево AST над именами тегов в множество id объектов.
#
# Узел — либо строка (имя тега), либо массив [оператор, операнд, операнд, ...]:
#
#   "Hotel"                                      -> все объекты с тегом Hotel
#   ["Hotel", "Izola"]                            -> Hotel И Izola (оператор не указан — неявный and)
#   ["and", "Hotel", "Izola"]                     -> то же самое явно
#   ["or", "Hotel", "Hostel"]                     -> Hotel ИЛИ Hostel
#   ["and", ["or", "Hotel", "Hostel"], "Izola"]   -> (Hotel ИЛИ Hostel) И Izola
#   ["not", ["and", "Ankaran", "Koper"], "каменистый"]
#     -> (Ankaran И Koper) БЕЗ "каменистый" — not бинарный: левое минус правое
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

  def tag_ids(tag_name, klass)
    Set.new(klass.joins(:tags).where(tags: { name: tag_name }).pluck(:id))
  end
end
