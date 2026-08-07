class RemoveSlugFromTagsSchemasLabels < ActiveRecord::Migration[6.1]
  def change
    remove_column :tags, :slug, :string
    remove_column :schemas, :slug, :string
    remove_column :labels, :slug, :string
  end
end
