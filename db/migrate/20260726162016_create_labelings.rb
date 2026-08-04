class CreateLabelings < ActiveRecord::Migration[6.1]
  def change

    create_table :labelings do |t|
      t.integer "profile_id"
      t.integer "label_id"
      t.timestamps

    end

    add_index :labelings, :profile_id
    add_index :labelings, :label_id
    add_index :labelings, [:label_id, :profile_id], unique: true

  end
end


