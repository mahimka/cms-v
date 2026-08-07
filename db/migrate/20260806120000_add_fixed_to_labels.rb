class AddFixedToLabels < ActiveRecord::Migration[6.1]
  def change
    add_column :labels, :fixed, :boolean, default: false
  end
end
