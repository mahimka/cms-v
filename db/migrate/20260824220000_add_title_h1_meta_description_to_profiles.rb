class AddTitleH1MetaDescriptionToProfiles < ActiveRecord::Migration[6.1]
  def change
    add_column :profiles, :title, :string
    add_column :profiles, :h1, :string
    add_column :profiles, :meta_description, :text
  end
end
