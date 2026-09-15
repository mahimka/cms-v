# "ad.rb" сортируется раньше "concerns/" (require_all грузит app/**/*.rb
# одним проходом по алфавиту, без повторных попыток) — без явного
# require здесь PreventDestroyWithChildren ещё не будет определён.
require_relative "concerns/prevent_destroy_with_children"

class Ad < ActiveRecord::Base
  include PreventDestroyWithChildren

  has_ancestry

  # geonames feature_code для стран (PCLI и варианты) — см. AdsLists в
  # ~/projects/nearme, тот же список.
  COUNTRY_FEATURE_CODES = %w[PCLI PCLD TERR PCLIX PCLS PCLF PCL PCLH].freeze

  scope :active, -> { where(active: true) }

  validates :name, presence: true
  validates :slug, uniqueness: true, allow_nil: true

  before_destroy :prevent_destroy_if_tags_linked

  def self.ransackable_attributes(auth_object = nil)
    ["active", "id", "name", "slug", "feature_code", "country_code", "admin1_code", "admin2_code", "population", "ancestry", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["parent", "children"]
  end

  # Теги, привязанные к этому ad через общее поле table/table_id (не
  # настоящая полиморфная ассоциация Rails — table хранит имя таблицы
  # "ads", а не имя класса).
  def tags
    Tag.where(table: "ads", table_id: id)
  end

  # Код "своего" уровня: у страны — country_code, у ADM1 — admin1_code,
  # у ADM2 — admin2_code. У населённых пунктов (feature_code PPL*)
  # собственного admin-кода нет (это не административная единица) — nil.
  def own_level_code
    return country_code if COUNTRY_FEATURE_CODES.include?(feature_code)
    return admin1_code if feature_code == "ADM1"
    return admin2_code if feature_code == "ADM2"

    nil
  end

  private

  # table/table_id — не настоящий FK, Rails не может защитить эту связь
  # сам (как это делает has_many :details, dependent: :restrict_with_error
  # у Label) — проверяем вручную.
  def prevent_destroy_if_tags_linked
    return if tags.none?

    errors.add(:base, "нельзя удалить — есть теги, ссылающиеся на этот ad (#{tags.pluck(:name).join(', ')})")
    throw :abort
  end
end
