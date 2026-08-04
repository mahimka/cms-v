# app/models/history.rb

# я Claude (2026-08-02): History хранит редиректы со старых uri
# опубликованных страниц на новые — записи создаются автоматически
# из Page при смене uri (см. Page#record_uri_history). Роутинг,
# который будет проверять эту таблицу для 404 на несуществующих uri,
# добавляется отдельно, позже.
class History < ActiveRecord::Base
  belongs_to :page, optional: true

  validates :old_uri,
            presence: true,
            uniqueness: true

  validates :new_uri,
            presence: true

  validates :redirect_code,
            presence: true,
            numericality: { only_integer: true }

  # я Claude (2026-08-02): allowlist полей для ransack (поиск в /admin/histories).
  def self.ransackable_attributes(auth_object = nil)
    [
      "old_uri",
      "new_uri",
      "redirect_code",
      "page_id",
      "created_at",
      "updated_at"
    ]
  end
end
