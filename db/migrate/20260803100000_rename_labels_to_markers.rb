class RenameLabelsToMarkers < ActiveRecord::Migration[6.1]
  def change
    rename_table :labels, :markers
    rename_table :labelings, :profile_markers
    rename_column :profile_markers, :label_id, :marker_id
  end
end
