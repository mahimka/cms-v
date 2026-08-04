class SchemaLabel < ActiveRecord::Base
  belongs_to :schema
  belongs_to :label

  validates :label_id, uniqueness: { scope: :schema_id }
end
