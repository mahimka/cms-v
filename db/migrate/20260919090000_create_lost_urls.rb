class CreateLostUrls < ActiveRecord::Migration[6.1]
  def change
    create_table :lost_urls do |t|
      t.string :path, null: false
      t.string :referrer
      t.string :ip
      t.integer :hits_count, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.boolean :reviewed, null: false, default: false

      t.timestamps
    end

    add_index :lost_urls, :path, unique: true
  end
end
