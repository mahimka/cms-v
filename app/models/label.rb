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

  before_destroy :prevent_destroy_unless_inactive_and_unfixed

  validates :name, presence: true, uniqueness: true

  # Перевод name на язык страницы. Переводы вносятся вручную в админке
  # (translations — hash locale => строка), при отсутствии — фолбэк на name.
  def translation(lang)
    translations&.dig(lang.to_s).presence || name
  end

  # Сколько раз этот label используется в Detail — всего, либо только
  # у Entity/Item/Event конкретной schema (details не хранит schema_id
  # напрямую — он есть только у detailable, поэтому считаем по каждому
  # полиморфному типу отдельно).
  def usage_count(schema: nil)
    return details.count unless schema

    %w[Entity Item Event].sum do |type|
      klass = type.constantize
      details.where(detailable_type: type, detailable_id: klass.where(schema_id: schema.id)).count
    end
  end

  def self.ransackable_attributes(auth_object = nil)
    ["active", "id", "name", "field_type", "position", "ancestry", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["parent", "children"]
  end

  private

  # Удалять можно только заведомо выведенный из оборота label — сперва
  # сними active и fixed вручную, чтобы удаление не было случайным.
  def prevent_destroy_unless_inactive_and_unfixed
    return if !active? && !fixed?

    errors.add(:base, "нельзя удалить — сначала снимите active и fixed")
    throw :abort
  end
end
