class CreateTaggings < ActiveRecord::Migration[6.1]
  def change
    create_table "taggings" do |t|
      t.integer "tag_id"
      t.integer "taggable_id"
      t.string "taggable_type", limit: 20
      t.datetime "created_at"
      t.datetime "updated_at"
      t.index ["tag_id", "taggable_id", "taggable_type"], name: "index_taggings_on_tag_id_and_taggable_id_and_taggable_type", unique: true
      t.index ["tag_id"], name: "index_taggings_on_tag_id"
      t.index ["taggable_id", "taggable_type"], name: "index_taggings_on_taggable_id_and_taggable_type"
    end
    
  end
end
