class CreateSchemas < ActiveRecord::Migration[6.1]
  def change
    create_table :schemas do |t|
      t.string :ancestry
      t.string :name, null: false
      t.string :slug
      t.string :schema_org_url
      t.text :json_ld_template
      t.integer :position
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :schemas, :ancestry
    add_index :schemas, :slug, unique: true
  end
end
