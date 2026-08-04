class AddEan < ActiveRecord::Migration[6.1]
  def change
    add_column :products, :ean, :string, limit: 14
    add_index :products, :ean, unique: true
  end
end
