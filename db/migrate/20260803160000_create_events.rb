class CreateEvents < ActiveRecord::Migration[6.1]
  def change
    create_table :events do |t|
      t.boolean :active, default: true
      t.boolean :published, default: false

      t.string :name, null: false
      t.references :schema, foreign_key: true

      t.datetime :start_at
      t.datetime :end_at

      t.references :venue, foreign_key: { to_table: :entities }
      t.string :address
      t.float :latitude
      t.float :longitude

      t.text :details

      t.timestamps
    end

    add_index :events, :name
    add_index :events, :start_at
  end
end
