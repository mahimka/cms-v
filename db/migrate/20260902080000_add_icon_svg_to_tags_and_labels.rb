class AddIconSvgToTagsAndLabels < ActiveRecord::Migration[6.1]
  def change
    add_column :tags, :icon_svg, :text
    add_column :labels, :icon_svg, :text
  end
end
