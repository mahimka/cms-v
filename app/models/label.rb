class Label < ActiveRecord::Base
  include FixedName
  fixed_name_fields :name
  include PreventDestroyWithChildren

  has_ancestry

  serialize :translations, JSON

  scope :active, -> { where(active: true) }

  has_many :schema_labels, dependent: :destroy
  has_many :schemas, through: :schema_labels

  has_many :links, dependent: :nullify

  # :nullify не подходит, как у links — Detail#label_id обязателен
  # (не optional), поэтому осиротевшая запись сломает set_numeric_value,
  # уникальность и Entity/Item/Event#details. Лейбл, используемый в
  # деталях, нельзя удалить, пока эти детали не удалены.
  has_many :details, dependent: :restrict_with_error

  validates :name, presence: true

  # Перевод name на язык страницы. Переводы вносятся вручную в админке
  # (translations — hash locale => строка), при отсутствии — фолбэк на name.
  def translation(lang)
    translations&.dig(lang.to_s).presence || name
  end

  def self.ransackable_attributes(auth_object = nil)
    ["active", "id", "name", "field_type", "position", "ancestry", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["parent", "children"]
  end
end
