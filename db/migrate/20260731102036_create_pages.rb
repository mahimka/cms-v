class CreatePages < ActiveRecord::Migration[6.1]
  def change
    create_table :pages do |t|
      t.boolean :ready, default: false
      t.boolean :published, default: false
      t.boolean :has_feed, default: false

      t.string :ancestry

      t.string :lang, null: false
      t.string :slug
      t.string :uri, null: false

      t.references :master,
                   null: true,
                   foreign_key: { to_table: :pages },
                   index: true

      t.string :title
      t.string :h1
      t.string :subtitle
      t.text :meta_description
      t.text :body
      t.text :faq
      t.text :schema

      t.string :anchor_1
      t.string :anchor_2
      t.string :anchor_3
      
      t.text :hero_1
      t.text :hero_2
      t.text :hero_3
      t.text :sidebar_1
      t.text :sidebar_2
      t.text :sidebar_3
      t.text :footer_1
      t.text :footer_2
      t.text :footer_3
      
      t.text :block_1
      t.text :block_2
      t.text :block_3
      t.text :block_4

      t.string :view
      t.string :layout
      
      t.string :pageable_type
      t.integer :pageable_id
      t.integer :list_id

      t.datetime :edited_at

      t.timestamps
    end

    add_index :pages, :uri, unique: true
    add_index :pages, :ancestry

    add_index :pages, [:master_id, :lang], 
              unique: true,
              where: "master_id IS NOT NULL",
              name: "index_pages_on_master_and_lang"
  end
end