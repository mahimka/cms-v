class RenameActiveToGeneratePagesOnPageableTypes < ActiveRecord::Migration[6.1]
  def change
    # У Entity/Item/Event "active" всегда значил одно: можно ли по
    # объекту сгенерировать страницу через генераторы (см.
    # PageTemplateGenerator#matching_objects, ListQuery#objects). Название
    # не отражало это — переименовываем, не меняя поведение и данные.
    rename_column :entities, :active, :generate_pages
    rename_column :items, :active, :generate_pages
    rename_column :events, :active, :generate_pages
  end
end
