class Schema < ActiveRecord::Base
  include FixedName
  fixed_name_fields :name, :slug

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

  # Группы тегов, привязанные к этому узлу целиком: свои + унаследованные
  # от всех предков (Hotel получает группы, назначенные на LodgingBusiness и Organization).
  # schema_tags хранит id родительских тегов (групп), а не отдельных тегов.
  def effective_tag_groups
    Tag.joins(:schema_tags).where(schema_tags: { schema_id: path_ids }).distinct
  end

  # Конкретные теги, допустимые для этого узла — активные дочерние теги привязанных групп.
  def effective_tags
    Tag.active.where(parent_id: effective_tag_groups.select(:id)).distinct
  end

  # Группы лейблов, привязанные к этому узлу целиком: свои + унаследованные
  # от всех предков. schema_labels хранит id корневых лейблов (групп), а не отдельных лейблов.
  def effective_label_groups
    Label.joins(:schema_labels).where(schema_labels: { schema_id: path_ids }).distinct
  end

  # Ключи details, допустимые для этого узла — активные дочерние лейблы привязанных групп,
  # с тем же наследованием по цепочке предков.
  def effective_labels
    child_ids = effective_label_groups.flat_map(&:child_ids)
    Label.active.where(id: child_ids).distinct
  end
end
