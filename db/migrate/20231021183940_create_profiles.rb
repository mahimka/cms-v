class CreateProfiles < ActiveRecord::Migration[6.1]
  def change
    create_table :profiles do |t|
      t.boolean "active", default: true
      t.integer "site_id"
      t.string :url
      t.string :profileable_type
      t.integer :profileable_id
      t.text :notes
      t.timestamps
      t.index :site_id

    end

    add_index :profiles, [:profileable_type, :profileable_id], unique: true

  end
end
