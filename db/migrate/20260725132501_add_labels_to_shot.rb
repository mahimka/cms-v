class AddLabelsToShot < ActiveRecord::Migration[6.1]
  def change
    add_column :shots, :name, :string
    add_column :shots, :labels, :text
  end
end
