class CreateLabels < ActiveRecord::Migration[6.1]
  def change

    create_table :labels do |t|
      t.boolean "active", default: true
      t.integer "site_id"
      t.integer "tag_id"
      t.string :group
      t.string :name
      t.string :details
      t.string :admin_notes
 
      t.timestamps

    end

    add_index :labels, :site_id
    add_index :labels, :tag_id
    add_index :labels, [:site_id, :group, :name], unique: true


  end
end
