class CreateSchemaDetailKeys < ActiveRecord::Migration[6.1]
  def change
    create_table :schema_detail_keys do |t|
      t.references :schema, null: false, foreign_key: true
      t.references :detail_key, null: false, foreign_key: true

      t.timestamps
    end

    add_index :schema_detail_keys, [:schema_id, :detail_key_id], unique: true, name: "index_schema_detail_keys_on_schema_and_detail_key"
  end
end
