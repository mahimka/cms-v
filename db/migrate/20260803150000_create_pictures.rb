class CreatePictures < ActiveRecord::Migration[6.1]
  def change
    create_table :pictures do |t|
      t.boolean :active, default: true
      t.boolean :published, default: false

      t.string :imageable_type
      t.integer :imageable_id

      t.string :file
      t.string :alt
      t.text :translations

      t.string :content_type
      t.integer :width
      t.integer :height
      t.string :ratio

      t.integer :position

      t.timestamps
    end

    add_index :pictures, [:imageable_type, :imageable_id]
  end
end
