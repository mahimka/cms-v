class Schema < ActiveRecord::Base
  has_ancestry

  scope :active, -> { where(active: true) }

  has_many :schema_tags, dependent: :destroy
  has_many :tags, through: :schema_tags

  has_many :schema_labels, dependent: :destroy
  has_many :labels, through: :schema_labels

  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["active", "id", "name", "slug", "schema_org_url", "position", "ancestry", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["parent", "children"]
  end

  # Теги, допустимые для этого узла: свои + унаследованные от всех
  # предков (Hotel получает то, что назначено на LodgingBusiness и Organization).
  def effective_tags
    Tag.joins(:schema_tags).where(schema_tags: { schema_id: path_ids }).distinct
  end

  # Ключи details, допустимые для этого узла, с тем же наследованием по цепочке предков.
  def effective_labels
    Label.joins(:schema_labels).where(schema_labels: { schema_id: path_ids }).distinct
  end
end
