class AddBlock5And6ToPages < ActiveRecord::Migration[6.1]
  def change
    add_column :pages, :block_5, :text
    add_column :pages, :block_6, :text
  end
end
