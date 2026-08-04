class Marker < ActiveRecord::Base

  scope :active, -> { where(active: true) }

  has_many :profile_markers, :dependent => :destroy
  has_many :profiles, :through => :profile_markers



  belongs_to :site
  belongs_to :tag

end
