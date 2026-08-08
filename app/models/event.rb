class Event < ActiveRecord::Base
  include Taggable
  include SchemaIdentifiable
  include Pageable

  serialize :details, JSON

  validates :name, presence: true
  validates :schema, presence: true

  scope :active, -> { where(active: true) }
  scope :published, -> { where(published: true) }
  scope :upcoming, -> { where("start_at >= ?", Time.current) }

  belongs_to :schema
  belongs_to :venue, class_name: "Entity", optional: true

  has_many :profiles, as: :profileable, dependent: :destroy
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

  # Если у события нет своего адреса/координат — берём их у venue
  # (Entity места проведения), если он задан.
  def effective_address
    address.presence || venue&.address
  end

  def effective_latitude
    latitude || venue&.latitude
  end

  def effective_longitude
    longitude || venue&.longitude
  end

end
