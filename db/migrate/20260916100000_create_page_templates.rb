class CreatePageTemplates < ActiveRecord::Migration[6.1]
  def change
    create_table :page_templates do |t|
      # ready/published, которые нужно проставить сгенерированной по
      # этому template странице (не самого template).
      t.boolean :page_ready, default: false
      t.boolean :page_published, default: false

      t.string :template_type # "Profile" | "List"
      t.string :pageable_type # "Entity" | "Item" | "Event" | "Picture"
      t.text :template_conditions # какие объекты pageable_type получают страницу по этому template

      t.string :parent_page_id # родитель для генерируемых страниц — id существующей НЕ сгенерированной страницы (Page#template_id nil/0)
      t.string :slug
      t.text :conditions # conditions самой генерируемой страницы (для template_type "List")

      t.string :lang, null: false

      t.string :view
      t.string :layout

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
      t.text :block_5
      t.text :block_6

      t.timestamps
    end
  end
end
