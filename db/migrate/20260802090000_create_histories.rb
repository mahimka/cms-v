class CreateHistories < ActiveRecord::Migration[6.1]
  def change
    create_table :histories do |t|
      t.string :old_uri, null: false
      t.string :new_uri, null: false
      t.integer :redirect_code, null: false, default: 301

      t.references :page,
                   null: true,
                   foreign_key: true,
                   index: true

      t.timestamps
    end

    add_index :histories, :old_uri, unique: true
  end
end
