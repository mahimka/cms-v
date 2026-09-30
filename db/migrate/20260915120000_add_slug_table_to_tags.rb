class AddSlugTableToTags < ActiveRecord::Migration[6.1]
  def change
    add_column :tags, :slug, :string
    add_column :tags, :table, :string
    add_column :tags, :table_id, :integer

    remove_index :tags, name: "index_tags_on_name"
    add_index :tags, :slug, unique: true, name: "index_tags_on_slug"
  end
end
