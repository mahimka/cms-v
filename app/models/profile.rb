class Profile < ActiveRecord::Base

  scope :active, -> { where(active: true) }
	
  belongs_to :site

  belongs_to :profileable, polymorphic: true # I need profiles of makers as well!
  # belongs_to :product 

  has_many :snap_shots, dependent: :destroy

  has_many :profile_markers, dependent: :destroy
  has_many :markers, :through => :profile_markers

  validates :site_id, :url, presence: true
  # validates :name, uniqueness: true


  # Opt-in attributes
  def self.ransackable_attributes(auth_object = nil)
    [
      "active", 
      "site_id",
      "url",
      "profileable_type",
      "profileable_id",
      "notes",
      "created_at", 
      "updated_at", 
      "redirected",
      "redirected_to",
      "status",
      "scraped_at"
    ]
  end

  # # Do NOT include :shotable in ransackable_associations!
  # def self.ransackable_associations(auth_object = nil)
  #   ["profileable_type"] # or non-polymorphic associations like ["user"]
  # end


end

