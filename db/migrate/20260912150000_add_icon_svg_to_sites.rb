class AddIconSvgToSites < ActiveRecord::Migration[6.1]
  def change
    add_column :sites, :icon_svg, :text
  end
end
