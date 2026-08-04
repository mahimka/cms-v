class CreateSchemaTags < ActiveRecord::Migration[6.1]
  def change
    create_table :schema_tags do |t|
      t.references :schema, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :schema_tags, [:schema_id, :tag_id], unique: true
  end
end
