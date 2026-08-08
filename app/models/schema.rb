class Schema < ActiveRecord::Base
  include FixedName
  fixed_name_fields :name

  has_ancestry

  scope :active, -> { where(active: true) }

  has_many :schema_tags, dependent: :destroy
  has_many :tags, through: :schema_tags

  has_many :schema_labels, dependent: :destroy
  has_many :labels, through: :schema_labels

  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["active", "id", "name", "schema_org_url", "position", "ancestry", "created_at", "updated_at"]
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

  # { schema_id => [tag_id, ...] } — effective_tags сразу для набора схем,
  # одним проходом по schema_tags/tags вместо N+1 от вызова #effective_tags
  # у каждой схемы по отдельности. Нужен для конструктора conditions
  # страниц-списков (там список тегов пересчитывается для всех активных
  # схем сразу, на клиенте).
  def self.effective_tag_ids_map(schemas)
    group_ids_by_schema = SchemaTag.pluck(:schema_id, :tag_id)
      .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(schema_id, tag_id), h| h[schema_id] << tag_id }

    child_ids_by_group = Tag.active.where.not(parent_id: nil).pluck(:parent_id, :id)
      .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(parent_id, id), h| h[parent_id] << id }

    schemas.each_with_object({}) do |schema, map|
      group_ids = schema.path_ids.flat_map { |id| group_ids_by_schema[id] }
      map[schema.id] = group_ids.flat_map { |group_id| child_ids_by_group[group_id] }.uniq
    end
  end
end
