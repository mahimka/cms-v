class CreateLinks < ActiveRecord::Migration[6.1]
  def change
    create_table :links do |t|
      t.boolean :active, default: true
      t.boolean :ready, default: false
      t.boolean :published, default: false

      t.string :linkable_type
      t.integer :linkable_id

      t.integer :label_id

      t.string :url, limit: 255

      t.datetime :checked_at
      t.string :response

      t.timestamps
    end

    add_index :links, [:linkable_type, :linkable_id]
    add_index :links, :label_id
  end
end
