class AddPageUriToPageTemplates < ActiveRecord::Migration[6.1]
  def change
    # Только для template_type "Profile": полный путь страницы, например
    # "/[addressLocality.slug]/beaches/{name}". Пустое — как раньше
    # (parent_page_id + slug). См. PageTemplateGenerator class-comment.
    add_column :page_templates, :page_uri, :string unless column_exists?(:page_templates, :page_uri)
  end
end
