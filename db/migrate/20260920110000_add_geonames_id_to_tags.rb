class AddGeonamesIdToTags < ActiveRecord::Migration[6.1]
  def change
    add_column :tags, :geonames_id, :integer
    add_index :tags, :geonames_id
  end
end
