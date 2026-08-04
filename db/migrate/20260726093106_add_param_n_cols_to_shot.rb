class AddParamNColsToShot < ActiveRecord::Migration[6.1]
  def change
    add_column :shots, :param_1, :string
    add_column :shots, :param_2, :string
    add_column :shots, :param_3, :string
    add_column :shots, :param_4, :string
    add_column :shots, :param_5, :string
  end
end
