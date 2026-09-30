class DropAdsAndClearTagTableRefs < ActiveRecord::Migration[6.1]
  def up
    execute "UPDATE tags SET \"table\" = NULL, table_id = NULL"
    drop_table :ads
  end

  def down
    create_table :ads do |t|
      t.string "ancestry"
      t.string "name"
      t.string "slug"
      t.string "feature_code"
      t.string "country_code"
      t.string "admin1_code"
      t.string "admin2_code"
      t.integer "population"
      t.float "latitude"
      t.float "longitude"
      t.string "timezone"
      t.boolean "active", default: true
      t.timestamps precision: 6, null: false
      t.string "short"
      t.index ["ancestry"]
      t.index ["feature_code"]
      t.index ["slug"], unique: true
    end
    # table/table_id значения не восстановимы — down только про схему.
  end
end
