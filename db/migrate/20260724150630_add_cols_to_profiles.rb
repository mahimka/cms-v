class AddColsToProfiles < ActiveRecord::Migration[6.1]
  def change
    add_column :profiles, :redirected, :boolean
    add_column :profiles, :redirected_to, :string
    add_column :profiles, :status, :string
    add_column :profiles, :scraped_at, :datetime
  end
end
