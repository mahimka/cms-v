class ReplaceListIdWithConditionsOnPages < ActiveRecord::Migration[6.1]
  def change
    remove_column :pages, :list_id, :integer
    add_column :pages, :conditions, :text
  end
end
