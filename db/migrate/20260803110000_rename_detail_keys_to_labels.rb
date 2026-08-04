class RenameDetailKeysToLabels < ActiveRecord::Migration[6.1]
  def change
    rename_table :detail_keys, :labels
    rename_table :schema_detail_keys, :schema_labels
    rename_column :schema_labels, :detail_key_id, :label_id
  end
end
