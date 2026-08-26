class AddRatingReviewCountToProfiles < ActiveRecord::Migration[6.1]
  def change
    add_column :profiles, :rating, :float
    add_column :profiles, :review_count, :integer
  end
end
