class AddParentPageUriToPageTemplates < ActiveRecord::Migration[6.1]
  def change
    # Только для template_type "ProfileUri": uri страницы-родителя, например
    # "/[addressLocality.slug]/beaches". См. PageTemplateGenerator class-comment.
    add_column :page_templates, :parent_page_uri, :string unless column_exists?(:page_templates, :parent_page_uri)
  end
end
