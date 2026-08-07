# List#conditions ссылается на теги/схемы по строковому ключу (Tag —
# по name, Schema — по slug), а не по id (id нестабилен между
# реимпортами). Если это поле можно менять свободно, любая ссылка из
# List молча перестаёт находить объект. fixed: true — явный признак
# "на это значение уже кто-то ссылается, дальше руками не трогать".
module FixedName
  extend ActiveSupport::Concern

  class_methods do
    def fixed_name_fields(*fields)
      @fixed_name_fields = fields.flatten.map(&:to_s)
    end

    def fixed_name_field_list
      @fixed_name_fields || ["name"]
    end
  end

  included do
    validate :protected_fields_unchanged_if_fixed, on: :update
  end

  private

  def protected_fields_unchanged_if_fixed
    return unless fixed?

    self.class.fixed_name_field_list.each do |field|
      next unless attribute_changed?(field)

      errors.add(field, "нельзя менять — запись помечена fixed: true")
    end
  end
end
