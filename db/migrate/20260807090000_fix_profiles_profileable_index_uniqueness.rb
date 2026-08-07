class FixProfilesProfileableIndexUniqueness < ActiveRecord::Migration[6.1]
  def change
    # Уникальный индекс ошибочно ограничивал одну сущность одним профилем
    # вообще (на любом сайте), хотя интерфейс уже позволяет добавлять
    # несколько профилей на разных сайтах (booking.com, tripadvisor.com...)
    remove_index :profiles, name: "index_profiles_on_profileable_type_and_profileable_id"
    add_index :profiles, [:profileable_type, :profileable_id]
  end
end
