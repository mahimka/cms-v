class CreateDetailKeys < ActiveRecord::Migration[6.1]
  def change
    create_table :detail_keys do |t|
      t.string :ancestry
      t.string :name, null: false
      t.string :slug
      t.string :field_type, default: "string"
      t.integer :position
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :detail_keys, :ancestry
    add_index :detail_keys, :slug, unique: true
  end
end
