class RenameActiveToAliveOnLinksAndProfiles < ActiveRecord::Migration[6.1]
  def change
    # У Link/Profile "active" всегда значил результат последней проверки
    # (LinkChecker/CheckProfile): 200/жива vs 404/redirect/error — не
    # абстрактный "активна", а буквально "жива ли ссылка/профиль" (см.
    # комментарий в lib/link_checker.rb). Переименовываем под факт, не
    # меняя поведение и данные.
    rename_column :links, :active, :alive
    rename_column :profiles, :active, :alive
  end
end
