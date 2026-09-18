class AddListTagIdToPages < ActiveRecord::Migration[6.1]
  def change
    add_column :pages, :list_tag_id, :integer
  end
end
