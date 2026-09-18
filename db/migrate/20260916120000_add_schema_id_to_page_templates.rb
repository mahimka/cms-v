class AddSchemaIdToPageTemplates < ActiveRecord::Migration[6.1]
  def change
    # Доп. фильтр к template_conditions (тегам) — если задан, объекты
    # pageable_type ещё и должны принадлежать этой Schema (с поддеревом,
    # как в ListQuery). По умолчанию пустой — фильтр не применяется.
    add_column :page_templates, :schema_id, :integer
  end
end
