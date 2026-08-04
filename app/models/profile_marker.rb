class ProfileMarker < ActiveRecord::Base
  belongs_to :profile
  belongs_to :marker

  validates_uniqueness_of :marker_id, :scope => [:profile_id]
end
