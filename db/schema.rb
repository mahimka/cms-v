# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_08_26_150000) do

  create_table "details", force: :cascade do |t|
    t.string "detailable_type"
    t.integer "detailable_id"
    t.integer "label_id"
    t.text "value"
    t.float "numeric_value"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["detailable_type", "detailable_id", "label_id"], name: "index_details_on_detailable_and_label", unique: true
    t.index ["detailable_type", "detailable_id"], name: "index_details_on_detailable_type_and_detailable_id"
  end

  create_table "entities", force: :cascade do |t|
    t.boolean "active"
    t.string "name", null: false
    t.integer "parent_id"
    t.string "address"
    t.float "latitude"
    t.float "longitude"
    t.text "details"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "schema_id"
    t.index ["name"], name: "index_entities_on_name"
    t.index ["schema_id"], name: "index_entities_on_schema_id"
  end

  create_table "events", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "published", default: false
    t.string "name", null: false
    t.integer "schema_id"
    t.datetime "start_at"
    t.datetime "end_at"
    t.integer "venue_id"
    t.string "address"
    t.float "latitude"
    t.float "longitude"
    t.text "details"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "index_events_on_name"
    t.index ["schema_id"], name: "index_events_on_schema_id"
    t.index ["start_at"], name: "index_events_on_start_at"
    t.index ["venue_id"], name: "index_events_on_venue_id"
  end

  create_table "histories", force: :cascade do |t|
    t.string "old_uri", null: false
    t.string "new_uri", null: false
    t.integer "redirect_code", default: 301, null: false
    t.integer "page_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["old_uri"], name: "index_histories_on_old_uri", unique: true
    t.index ["page_id"], name: "index_histories_on_page_id"
  end

  create_table "items", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "ean", limit: 14
    t.boolean "active", default: true
    t.integer "schema_id"
    t.text "details"
    t.index ["active"], name: "index_items_on_active"
    t.index ["ean"], name: "index_items_on_ean", unique: true
    t.index ["name"], name: "index_items_on_name"
    t.index ["schema_id"], name: "index_items_on_schema_id"
  end

  create_table "labels", force: :cascade do |t|
    t.string "ancestry"
    t.string "name", null: false
    t.string "field_type", default: "string"
    t.integer "position"
    t.boolean "active", default: true
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "translations"
    t.boolean "fixed", default: false
    t.index ["ancestry"], name: "index_labels_on_ancestry"
    t.index ["name"], name: "index_labels_on_name", unique: true
  end

  create_table "links", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "ready", default: false
    t.boolean "published", default: false
    t.string "linkable_type"
    t.integer "linkable_id"
    t.integer "label_id"
    t.string "url", limit: 255
    t.datetime "checked_at"
    t.string "response"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["label_id"], name: "index_links_on_label_id"
    t.index ["linkable_type", "linkable_id"], name: "index_links_on_linkable_type_and_linkable_id"
  end

  create_table "markers", force: :cascade do |t|
    t.boolean "active", default: true
    t.integer "site_id"
    t.integer "tag_id"
    t.string "group"
    t.string "name"
    t.string "details"
    t.string "admin_notes"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["site_id", "group", "name"], name: "index_markers_on_site_id_and_group_and_name", unique: true
    t.index ["site_id"], name: "index_markers_on_site_id"
    t.index ["tag_id"], name: "index_markers_on_tag_id"
  end

  create_table "pages", force: :cascade do |t|
    t.boolean "ready", default: false
    t.boolean "published", default: false
    t.boolean "has_feed", default: false
    t.string "ancestry"
    t.string "lang", null: false
    t.string "slug"
    t.string "uri", null: false
    t.integer "master_id"
    t.string "title"
    t.string "h1"
    t.string "subtitle"
    t.text "meta_description"
    t.text "body"
    t.text "faq"
    t.text "schema"
    t.string "anchor_1"
    t.string "anchor_2"
    t.string "anchor_3"
    t.text "hero_1"
    t.text "hero_2"
    t.text "hero_3"
    t.text "sidebar_1"
    t.text "sidebar_2"
    t.text "sidebar_3"
    t.text "footer_1"
    t.text "footer_2"
    t.text "footer_3"
    t.text "block_1"
    t.text "block_2"
    t.text "block_3"
    t.text "block_4"
    t.string "view"
    t.string "layout"
    t.string "pageable_type"
    t.integer "pageable_id"
    t.datetime "edited_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "conditions"
    t.index ["ancestry"], name: "index_pages_on_ancestry"
    t.index ["master_id", "lang"], name: "index_pages_on_master_and_lang", unique: true, where: "master_id IS NOT NULL"
    t.index ["master_id"], name: "index_pages_on_master_id"
    t.index ["uri"], name: "index_pages_on_uri", unique: true
  end

  create_table "pictures", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "published", default: false
    t.string "imageable_type"
    t.integer "imageable_id"
    t.string "file"
    t.string "alt"
    t.text "translations"
    t.string "content_type"
    t.integer "width"
    t.integer "height"
    t.string "ratio"
    t.integer "position"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "user_id"
    t.float "latitude"
    t.float "longitude"
    t.datetime "taken_at"
    t.index ["imageable_type", "imageable_id"], name: "index_pictures_on_imageable_type_and_imageable_id"
    t.index ["user_id"], name: "index_pictures_on_user_id"
  end

  create_table "profile_markers", force: :cascade do |t|
    t.integer "profile_id"
    t.integer "marker_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["marker_id", "profile_id"], name: "index_profile_markers_on_marker_id_and_profile_id", unique: true
    t.index ["marker_id"], name: "index_profile_markers_on_marker_id"
    t.index ["profile_id"], name: "index_profile_markers_on_profile_id"
  end

  create_table "profiles", force: :cascade do |t|
    t.boolean "active", default: true
    t.integer "site_id"
    t.string "url"
    t.string "profileable_type"
    t.integer "profileable_id"
    t.text "notes"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "redirected"
    t.string "redirected_to"
    t.string "status"
    t.datetime "scraped_at"
    t.string "title"
    t.string "h1"
    t.text "meta_description"
    t.text "details"
    t.index ["profileable_type", "profileable_id"], name: "index_profiles_on_profileable_type_and_profileable_id"
    t.index ["site_id"], name: "index_profiles_on_site_id"
  end

  create_table "schema_labels", force: :cascade do |t|
    t.integer "schema_id", null: false
    t.integer "label_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["label_id"], name: "index_schema_labels_on_label_id"
    t.index ["schema_id", "label_id"], name: "index_schema_detail_keys_on_schema_and_detail_key", unique: true
    t.index ["schema_id"], name: "index_schema_labels_on_schema_id"
  end

  create_table "schema_tags", force: :cascade do |t|
    t.integer "schema_id", null: false
    t.integer "tag_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schema_id", "tag_id"], name: "index_schema_tags_on_schema_id_and_tag_id", unique: true
    t.index ["schema_id"], name: "index_schema_tags_on_schema_id"
    t.index ["tag_id"], name: "index_schema_tags_on_tag_id"
  end

  create_table "schemas", force: :cascade do |t|
    t.string "ancestry"
    t.string "name", null: false
    t.string "schema_org_url"
    t.text "json_ld_template"
    t.integer "position"
    t.boolean "active", default: true
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "fixed", default: false
    t.index ["ancestry"], name: "index_schemas_on_ancestry"
  end

  create_table "sites", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "domain"
    t.text "notes"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "snap_shots", force: :cascade do |t|
    t.integer "profile_id"
    t.text "html_content"
    t.boolean "parsed"
    t.datetime "parsed_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "name"
    t.text "labels"
    t.string "param_1"
    t.string "param_2"
    t.string "param_3"
    t.string "param_4"
    t.string "param_5"
    t.string "title"
    t.string "h1"
    t.text "meta_description"
    t.index "\"site_id\"", name: "index_shots_on_site_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.integer "tag_id"
    t.integer "taggable_id"
    t.string "taggable_type", limit: 20
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["tag_id", "taggable_id", "taggable_type"], name: "index_taggings_on_tag_id_and_taggable_id_and_taggable_type", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type"], name: "index_taggings_on_taggable_id_and_taggable_type"
  end

  create_table "tags", force: :cascade do |t|
    t.boolean "active", default: true
    t.integer "parent_id"
    t.integer "position"
    t.string "name"
    t.string "short"
    t.string "short_2"
    t.string "admin_notes"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "translations"
    t.boolean "fixed", default: false
    t.index ["name"], name: "index_tags_on_name", unique: true
    t.index ["parent_id"], name: "index_tags_on_parent_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "password_digest"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "entities", "schemas"
  add_foreign_key "events", "entities", column: "venue_id"
  add_foreign_key "events", "schemas"
  add_foreign_key "histories", "pages"
  add_foreign_key "items", "schemas"
  add_foreign_key "pages", "pages", column: "master_id"
  add_foreign_key "schema_labels", "labels"
  add_foreign_key "schema_labels", "schemas"
  add_foreign_key "schema_tags", "schemas"
  add_foreign_key "schema_tags", "tags"
end
