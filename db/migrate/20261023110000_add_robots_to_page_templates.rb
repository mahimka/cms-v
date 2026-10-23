# Значения robots_index / robots_follow, которые получает сгенерированная страница
# (см. AddRobotsToPages). По умолчанию "index, follow".
class AddRobotsToPageTemplates < ActiveRecord::Migration[6.1]
  def change
    add_column :page_templates, :page_robots_index,  :boolean, null: false, default: true unless column_exists?(:page_templates, :page_robots_index)
    add_column :page_templates, :page_robots_follow, :boolean, null: false, default: true unless column_exists?(:page_templates, :page_robots_follow)
  end
end
