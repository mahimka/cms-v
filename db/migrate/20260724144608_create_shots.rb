class CreateShots < ActiveRecord::Migration[6.1]
  def change
    create_table :shots do |t|

      t.integer "profile_id"
      t.text :html_content
      t.boolean :parsed
      t.datetime :parsed_at
      t.timestamps
      t.index :site_id

    end
  end

end
