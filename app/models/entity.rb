class Entity < ActiveRecord::Base

  serialize :details, JSON

  validates :name, presence: true

  scope :active, -> { where(active: true) }

  belongs_to :schema, optional: true

  has_many :pages, as: :pageable, dependent: :destroy
  has_many :profiles, as: :profileable, dependent: :destroy
  # accepts_nested_attributes_for :profiles, allow_destroy: true, :reject_if => proc { |attributes| attributes['url'].blank? }
  # validates_associated :profiles
  # has_many :ratings
  
  has_many :links, as: :linkable, dependent: :destroy
  has_many :pictures, as: :imageable, dependent: :destroy

  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  # Теги и ключи details, допустимые для формы редактирования —
  # определяются схемой сущности (с учётом иерархии Schema.org).
  def effective_tags
    schema ? schema.effective_tags : Tag.none
  end

  def effective_labels
    schema ? schema.effective_labels : Label.none
  end
end
