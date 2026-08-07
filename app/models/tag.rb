class Tag < ActiveRecord::Base
  include FixedName
  fixed_name_fields :name
  include PreventDestroyWithChildren

  serialize :translations, JSON

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "id", "name", "admin_notes", "parent_id", "position", "short", "slug", "updated_at"] 
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
  # validates_uniqueness_of :name

  # Перевод name на язык страницы. Переводы вносятся вручную в админке
  # (translations — hash locale => строка), при отсутствии — фолбэк на name.
  def translation(lang)
    translations&.dig(lang.to_s).presence || name
  end

  # # for forms:
  # def parenttag_and_tag
  #   "#{self.parent.name}" +  " :: " + "#{self.name}"
  # end

end