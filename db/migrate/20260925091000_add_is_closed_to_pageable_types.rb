class AddIsClosedToPageableTypes < ActiveRecord::Migration[6.1]
  def change
    # Отдельно от generate_pages: бизнес-факт "заведение/товар/событие
    # закрыто", а не флаг для генератора страниц. Нужен, чтобы явно
    # отмечать закрытые заведения/товары, не трогая generate_pages.
    add_column :entities, :is_closed, :boolean, default: false
    add_column :items, :is_closed, :boolean, default: false
    add_column :events, :is_closed, :boolean, default: false
  end
end
