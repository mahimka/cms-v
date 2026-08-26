class AddDetailsToProfiles < ActiveRecord::Migration[6.1]
  def change
    add_column :profiles, :details, :text
  end
end
