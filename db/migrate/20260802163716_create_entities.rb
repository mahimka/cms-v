class CreateEntities < ActiveRecord::Migration[6.1]
  def change
    create_table :entities do |t|
      t.boolean :active
      t.string :name, null: false
      t.integer :parent_id
      t.string :entity_type
      t.string :address
      t.float :latitude
      t.float :longitude
      t.text :details

      t.timestamps
    end

    add_index :entities, :name
  end
end
