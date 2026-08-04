class CreateTags < ActiveRecord::Migration[6.1]
  def change

    create_table :tags do |t|
      t.boolean :active, default: true
      t.integer :parent_id
      t.integer :position
      t.string :name
      t.string :slug
      t.string :short
      t.string :short_2
      t.string :admin_notes
 
      t.timestamps
    end

    add_index :tags, :parent_id
    add_index :tags, :name

  end
end
