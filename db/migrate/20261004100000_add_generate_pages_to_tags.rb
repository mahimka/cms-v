class AddGeneratePagesToTags < ActiveRecord::Migration[6.1]
  def change
    # Как generate_pages у Entity/Item/Event: тег участвует в генерации
    # страниц только когда флаг включён (по умолчанию выключен).
    add_column :tags, :generate_pages, :boolean, default: false unless column_exists?(:tags, :generate_pages)
  end
end
