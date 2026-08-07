class Picture < ActiveRecord::Base
  include Taggable

  serialize :translations, JSON

  scope :active, -> { where(active: true) }
  scope :published, -> { where(published: true) }

  belongs_to :imageable, polymorphic: true

  validates :file, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["active", "id", "imageable_type", "imageable_id", "file", "alt", "content_type", "width", "height", "ratio", "published", "position", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["imageable", "tags"]
  end

  # Alt-текст на язык страницы. Переводится вручную в админке
  # (translations — hash locale => строка), при отсутствии — фолбэк на alt.
  def translation(lang)
    translations&.dig(lang.to_s).presence || alt
  end

end
