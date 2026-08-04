class CreateSites < ActiveRecord::Migration[6.1]
  def change
    create_table :sites do |t|
      t.string "name"
      t.string "url"
      t.string "domain"
      t.text "notes"
      t.timestamps
    end
  end
end

