class Detail < ActiveRecord::Base
  belongs_to :detailable, polymorphic: true
  belongs_to :label

  validates :label_id, uniqueness: { scope: [:detailable_type, :detailable_id] }

  before_save :set_numeric_value

  def self.ransackable_attributes(auth_object = nil)
    %w[id detailable_type detailable_id label_id value numeric_value created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[detailable label]
  end

  private

  # numeric_value индексируется и годится для диапазонных запросов
  # (price > 100 и т.п.) — заполняется только для лейблов, у которых
  # field_type это число. rescue nil — мягкий парсинг, не блокирует
  # сохранение при мусорном вводе в числовое поле.
  def set_numeric_value
    self.numeric_value = (Float(value) rescue nil) if %w[integer float].include?(label&.field_type)
  end
end
