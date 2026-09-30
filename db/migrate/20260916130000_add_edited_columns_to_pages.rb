class AddEditedColumnsToPages < ActiveRecord::Migration[6.1]
  def change
    # Массив имён полей (JSON), которые правили руками через обычную
    # форму /admin/pages/:id — PageTemplateGenerator с force: true их
    # не перезаписывает (см. Page::PROTECTABLE_FIELDS). Пусто — ничего
    # не защищено.
    add_column :pages, :edited_columns, :text
  end
end
