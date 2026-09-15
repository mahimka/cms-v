class Tag < ActiveRecord::Base
  include FixedName
  fixed_name_fields :name
  include PreventDestroyWithChildren

  serialize :translations, JSON

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "id", "name", "admin_notes", "parent_id", "position", "short", "updated_at"]
  end

  scope :active, -> { where(active: true) }
  scope :parenttags, -> { where(parent_id: [nil, 0]) }

  belongs_to :parent, class_name: "Tag", foreign_key: :parent_id, optional: true
  has_many :children, class_name: "Tag", foreign_key: :parent_id


  has_many :taggings, :dependent => :destroy

  has_many :items, :through => :taggings, :source => :taggable, :source_type => "Item"

  has_many :markers

  has_many :schema_tags, dependent: :destroy
  has_many :schemas, through: :schema_tags

  validates_presence_of :name #, :position
  validates :name, uniqueness: true
  validates :slug, uniqueness: true, allow_nil: true

  GEONAMES_SYNCED_FIELDS = %w[name slug].freeze

  # table == "ads" — данные тега пришли из Ad (см. Ad#tags) и дальше
  # должны обновляться только через перепривязку к ads, а не руками в
  # форме тега — иначе они разъедутся с source of truth. Проверяем
  # table_was, а не table, чтобы не блокировать самую первую привязку
  # (когда table/name/slug выставляются в одном save).
  validate :protected_fields_unchanged_if_from_ads, on: :update

  # Перевод name на язык страницы. Переводы вносятся вручную в админке
  # (translations — hash locale => строка), при отсутствии — фолбэк на name.
  def translation(lang)
    translations&.dig(lang.to_s).presence || name
  end

  # Сколько объектов (любого taggable-типа — Item/Entity/Event/Page/
  # Picture) помечено этим тегом.
  def usage_count
    taggings.count
  end

  # Ad, из которого взяты данные — обратная сторона Ad#tags.
  def ad
    Ad.find_by(id: table_id) if table == "ads"
  end

  # # for forms:
  # def parenttag_and_tag
  #   "#{self.parent.name}" +  " :: " + "#{self.name}"
  # end

  private

  def protected_fields_unchanged_if_from_ads
    return unless table_was == "ads"

    GEONAMES_SYNCED_FIELDS.each do |field|
      next unless attribute_changed?(field)

      errors.add(field, "нельзя менять вручную — тег привязан к ads (table_id=#{table_id}), обновляйте через перепривязку")
    end
  end

end