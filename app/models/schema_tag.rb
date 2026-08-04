class SchemaTag < ActiveRecord::Base
  belongs_to :schema
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :schema_id }
end
