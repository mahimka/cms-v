class AddParentTemplateIdToPageTemplates < ActiveRecord::Migration[6.1]
  def change
    add_column :page_templates, :parent_template_id, :integer
  end
end
