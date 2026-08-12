class CreateDetails < ActiveRecord::Migration[6.1]
  def change
    create_table :details do |t|
      t.string  :detailable_type
      t.integer :detailable_id
      t.integer :label_id
      t.text    :value
      t.float   :numeric_value

      t.timestamps
    end

    add_index :details, [:detailable_type, :detailable_id]
    add_index :details, [:detailable_type, :detailable_id, :label_id],
              unique: true, name: "index_details_on_detailable_and_label"
  end
end
