class AddArchivedToDetails < ActiveRecord::Migration[6.1]
  def change
    # Значение устарело (например телефон больше не актуален), но всё
    # ещё может иметь смысл показывать в архивных/закрытых записях
    # (Entity#is_closed) — в отличие от обычного удаления detail.
    add_column :details, :archived, :boolean, default: false
  end
end
