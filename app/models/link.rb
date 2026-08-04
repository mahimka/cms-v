class Link < ActiveRecord::Base

  scope :active, -> { where(active: true) }

  belongs_to :linkable, polymorphic: true
  belongs_to :label, optional: true

  validates :url, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["active", "id", "linkable_type", "linkable_id", "label_id", "url", "ready", "published", "checked_at", "response", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["linkable", "label"]
  end

end
