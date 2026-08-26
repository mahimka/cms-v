class AddTitleH1MetaDescriptionToSnapShots < ActiveRecord::Migration[6.1]
  def change
    add_column :snap_shots, :title, :string
    add_column :snap_shots, :h1, :string
    add_column :snap_shots, :meta_description, :text
  end
end
