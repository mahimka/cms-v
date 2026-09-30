class CreateAds < ActiveRecord::Migration[6.1]
  def change
    # id НЕ автоинкрементный по смыслу — заполняется вручную из geonames.org
    # geonameid при создании записи (SQLite это позволяет и для обычного
    # integer primary key, отдельный id:false не нужен).
    create_table :ads do |t|
      t.string :ancestry
      t.string :name
      t.string :slug
      t.string :feature_code
      t.string :country_code
      t.string :admin1_code
      t.string :admin2_code
      t.integer :population
      t.float :latitude
      t.float :longitude
      t.string :timezone
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :ads, :ancestry
    add_index :ads, :slug, unique: true
    add_index :ads, :feature_code
  end
end
