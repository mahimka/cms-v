class Item < ActiveRecord::Base
  include Taggable
  include SchemaIdentifiable
  include Pageable

  validates :name, presence: true
  validates :schema, presence: true

  scope :active, -> { where(active: true) }

  belongs_to :schema

  has_many :profiles, as: :profileable, dependent: :destroy
  # accepts_nested_attributes_for :profiles, allow_destroy: true, :reject_if => proc { |attributes| attributes['url'].blank? }
  # validates_associated :profiles
  # has_many :ratings

  has_many :links, as: :linkable, dependent: :destroy
  has_many :pictures, as: :imageable, dependent: :destroy

  # detail_records, а не details — иначе сгенерированный has_many-метод
  # details (relation) перекрыл бы метод details ниже (Hash, ради обратной
  # совместимости со старым serialize :details, JSON).
  has_many :detail_records, as: :detailable, class_name: "Detail", dependent: :destroy

  # Теги и ключи details, допустимые для формы редактирования —
  # определяются схемой сущности (с учётом иерархии Schema.org).
  def effective_tags
    schema ? schema.effective_tags : Tag.none
  end

  def effective_labels
    schema ? schema.effective_labels : Label.none
  end

  # Обратная совместимость с прежним serialize :details, JSON — Hash
  # {имя_label => значение}, как читали list_query.rb и шаблоны сайта.
  def details
    detail_records.includes(:label).order("labels.position, labels.name")
                   .each_with_object({}) { |d, h| h[d.label.name] = d.value }
  end
end
