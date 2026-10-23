# <meta name="robots">: robots_index -> index/noindex, robots_follow -> follow/nofollow.
# По умолчанию (и у всех существующих страниц) "index, follow".
class AddRobotsToPages < ActiveRecord::Migration[6.1]
  def change
    add_column :pages, :robots_index,  :boolean, null: false, default: true unless column_exists?(:pages, :robots_index)
    add_column :pages, :robots_follow, :boolean, null: false, default: true unless column_exists?(:pages, :robots_follow)
  end
end
