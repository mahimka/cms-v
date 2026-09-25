class Link < ActiveRecord::Base

  scope :alive, -> { where(alive: true) }

  belongs_to :linkable, polymorphic: true
  belongs_to :label, optional: true

  validates :url, presence: true

  # Случайный пробел на конце/в начале (вставка из адресной строки, копипаст
  # и т.п.) не видно глазами в input-поле, а URI.parse от него падает с
  # InvalidURIError — так что LinkChecker падал на "check" вместо проверки.
  before_validation { self.url = url.strip if url.is_a?(String) }

  # См. lib/link_checker.rb — единая логика "жива ли ссылка" для
  # tasks/links.rake и кнопок в админке.
  def check!
    LinkChecker.apply!(self)
  end

  def self.ransackable_attributes(auth_object = nil)
    ["alive", "id", "linkable_type", "linkable_id", "label_id", "url", "ready", "published", "checked_at", "response", "redirected", "redirected_to", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["linkable", "label"]
  end

end
