class AddOnlyMarkedTagsToPageTemplates < ActiveRecord::Migration[6.1]
  def change
    # Только для List со страницей на значение группы тегов (slug содержит
    # тег-блок): создавать страницы лишь для тегов с tags.generate_pages.
    add_column :page_templates, :only_marked_tags, :boolean, default: false unless column_exists?(:page_templates, :only_marked_tags)
  end
end
