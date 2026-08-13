class AddUniqueIndexToTagsName < ActiveRecord::Migration[6.1]
  def change
    # Модельная validates :name, uniqueness: true одна не защищает от
    # гонки (два одновременных INSERT), нужен и уникальный индекс в БД —
    # тот же приём, что у schema_labels (label_id/schema_id).
    remove_index :tags, name: "index_tags_on_name"
    add_index :tags, :name, unique: true
  end
end
