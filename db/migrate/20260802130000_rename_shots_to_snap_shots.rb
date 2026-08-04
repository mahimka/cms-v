class RenameShotsToSnapShots < ActiveRecord::Migration[6.1]
  def change
    rename_table :shots, :snap_shots
  end
end
