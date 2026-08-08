class Entity < ActiveRecord::Base
  include Taggable
  include SchemaIdentifiable
  include Pageable
  include PreventDestroyWithChildren

  serialize :details, JSON

  validates :name, presence: true
  validates :schema, presence: true

  scope :active, -> { where(active: true) }

  # Координаты уже есть в latitude/longitude при импорте — reverse_geocoded_by
  # только даёт .near(...), сам ничего не геокодирует. extend обязателен
  # именно в Sinatra (без Railtie) — см. тот же приём в старом Page.
  extend Geocoder::Model::ActiveRecord
  reverse_geocoded_by :latitude, :longitude

  belongs_to :schema

  # parent_id — колонка была, association — нет: ransack не мог
  # обратиться к "parent" (parent_name_cont и т.п.) без belongs_to.
  belongs_to :parent, class_name: "Entity", optional: true
  has_many :children, class_name: "Entity", foreign_key: :parent_id

  has_many :profiles, as: :profileable, dependent: :destroy
  # accepts_nested_attributes_for :profiles, allow_destroy: true, :reject_if => proc { |attributes| attributes['url'].blank? }
  # validates_associated :profiles
  # has_many :ratings
  
  has_many :links, as: :linkable, dependent: :destroy
  has_many :pictures, as: :imageable, dependent: :destroy

  # Теги и ключи details, допустимые для формы редактирования —
  # определяются схемой сущности (с учётом иерархии Schema.org).
  def effective_tags
    schema ? schema.effective_tags : Tag.none
  end

  def effective_labels
    schema ? schema.effective_labels : Label.none
  end
end
