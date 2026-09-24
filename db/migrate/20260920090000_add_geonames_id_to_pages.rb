class AddGeonamesIdToPages < ActiveRecord::Migration[6.1]
  def change
    add_column :pages, :geonames_id, :integer
    add_index :pages, :geonames_id
  end
end
