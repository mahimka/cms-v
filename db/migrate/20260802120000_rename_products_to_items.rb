class RenameProductsToItems < ActiveRecord::Migration[6.1]
  def up
    rename_table :products, :items

    # Полиморфные *_type колонки хранят имя класса как строку —
    # переименование класса само по себе их не обновляет.
    execute "UPDATE profiles SET profileable_type = 'Item' WHERE profileable_type = 'Product'"
    execute "UPDATE taggings SET taggable_type = 'Item' WHERE taggable_type = 'Product'"
    execute "UPDATE pages SET pageable_type = 'Item' WHERE pageable_type = 'Product'"
  end

  def down
    execute "UPDATE profiles SET profileable_type = 'Product' WHERE profileable_type = 'Item'"
    execute "UPDATE taggings SET taggable_type = 'Product' WHERE taggable_type = 'Item'"
    execute "UPDATE pages SET pageable_type = 'Product' WHERE pageable_type = 'Item'"

    rename_table :items, :products
  end
end
