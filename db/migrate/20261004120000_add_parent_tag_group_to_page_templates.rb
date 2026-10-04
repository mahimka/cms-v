class AddParentTagGroupToPageTemplates < ActiveRecord::Migration[6.1]
  def change
    # Только для List, подчинённого Profile-шаблону (parent_template_id):
    # имя группы тегов (например "addressLocality"), в которой лежит тег
    # страницы-родителя — ищется по совпадению Tag#slug и Page#slug родителя.
    # См. PageTemplateGenerator class-comment.
    add_column :page_templates, :parent_tag_group, :string unless column_exists?(:page_templates, :parent_tag_group)
  end
end
