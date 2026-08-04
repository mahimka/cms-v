class Tagging < ActiveRecord::Base

  # belongs_to :product
  # belongs_to :tag


  belongs_to :taggable, :polymorphic => true
  belongs_to :tag

  # validates_uniqueness_of :tag_id, :scope => [:taggable_id, :taggable_type]
  # validates :tag_id, :taggable_id, :presence => true
end