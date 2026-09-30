class AddPlusCodeToEntities < ActiveRecord::Migration[6.1]
  def change
    add_column :entities, :plus_code, :string
  end
end
