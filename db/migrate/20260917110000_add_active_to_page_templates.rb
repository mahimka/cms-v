class AddActiveToPageTemplates < ActiveRecord::Migration[6.1]
  def change
    add_column :page_templates, :active, :boolean, default: false
  end
end
