class Label < ActiveRecord::Base
  has_ancestry

  serialize :translations, JSON

  scope :active, -> { where(active: true) }

  has_many :schema_labels, dependent: :destroy
  has_many :schemas, through: :schema_labels

  has_many :links, dependent: :nullify

  validates :name, presence: true

  # Перевод name на язык страницы. Переводы вносятся вручную в админке
  # (translations — hash locale => строка), при отсутствии — фолбэк на name.
  def translation(lang)
    translations&.dig(lang.to_s).presence || name
  end

  def self.ransackable_attributes(auth_object = nil)
    ["active", "id", "name", "slug", "field_type", "position", "ancestry", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["parent", "children"]
  end
end
