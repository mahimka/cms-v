class AddSchemaAndDetailsToItems < ActiveRecord::Migration[6.1]
  def change
    add_reference :items, :schema, foreign_key: true
    add_column :items, :details, :text
  end
end
