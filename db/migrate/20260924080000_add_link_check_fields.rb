class AddLinkCheckFields < ActiveRecord::Migration[6.1]
  def change
    add_column :links, :redirected, :boolean, default: false
    add_column :links, :redirected_to, :string

    # Задержка (сек) между проверками ссылок с этим label — nil/0 значит
    # "можно параллельно" (обычные сайты), для facebook/instagram и
    # подобных площадок, где агрессивная проверка ведёт к блокировке,
    # выставляется вручную в /admin/labels — см. LinkChecker.
    add_column :labels, :check_delay_seconds, :integer
  end
end
