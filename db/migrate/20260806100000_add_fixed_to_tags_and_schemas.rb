class AddFixedToTagsAndSchemas < ActiveRecord::Migration[6.1]
  def change
    add_column :tags, :fixed, :boolean, default: false
    add_column :schemas, :fixed, :boolean, default: false
  end
end
