class AddUniqueIndexToLabelsName < ActiveRecord::Migration[6.1]
  def change
    # Тот же приём, что и у tags.name — модельная uniqueness одна не
    # защищает от гонки при одновременных INSERT.
    add_index :labels, :name, unique: true
  end
end
