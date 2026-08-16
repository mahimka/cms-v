class AddUploadFieldsToPictures < ActiveRecord::Migration[6.1]
  def change
    add_column :pictures, :user_id, :integer
    add_column :pictures, :latitude, :float
    add_column :pictures, :longitude, :float
    add_column :pictures, :taken_at, :datetime

    add_index :pictures, :user_id
  end
end
