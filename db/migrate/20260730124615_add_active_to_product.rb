class AddActiveToProduct < ActiveRecord::Migration[6.1]
  def change
    add_column :products, :active, :boolean, default: true
    add_index :products, :active
  end
end
