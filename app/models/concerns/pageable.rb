# Обратная сторона Page#pageable. pageable_type — MASTER_ONLY_FIELDS
# (пустой у переводов), поэтому обычный has_many :pages, as: :pageable
# находит только master-страницу — у переводов pageable_type не совпадает
# с фильтром ассоциации, хотя pageable_id у них тот же самый.
#
# Сначала находим master-страницы (у них pageable_type всегда верный),
# затем добавляем все их переводы через master_id.
module Pageable
  extend ActiveSupport::Concern

  included do
    before_destroy :prevent_destroy_if_pages_exist

    # page — не настоящая AR-ассоциация (см. комментарий выше), поэтому
    # ransack не может фильтровать по ней напрямую (pages_present и т.п.
    # не находят master-страницу через переводы). Даём то же самое через
    # scope + ransackable_scopes: q[with_page]=1 / q[without_page]=1.
    scope :with_page, lambda { |want = true|
      ids = Page.where(pageable_type: name).select(:pageable_id)
      ActiveRecord::Type::Boolean.new.cast(want) ? where(id: ids) : where.not(id: ids)
    }

    scope :without_page, lambda { |want = true|
      ids = Page.where(pageable_type: name).select(:pageable_id)
      ActiveRecord::Type::Boolean.new.cast(want) ? where.not(id: ids) : where(id: ids)
    }

    def self.ransackable_scopes(auth_object = nil)
      super + %i[with_page without_page]
    end
  end

  # Master-страница — единственная запись, где pageable_type реально
  # совпадает (у переводов он пустой). Одна на объект, поэтому singular.
  def page
    Page.find_by(pageable_type: self.class.name, pageable_id: id)
  end

  # Master + все её переводы.
  def pages
    master = page
    return Page.none unless master

    Page.where(master_id: master.id).or(Page.where(id: master.id))
  end

  private

  # Не destroy каскадом, а наоборот — удалить нельзя, пока есть хоть
  # одна ссылающаяся страница (master или перевод).
  def prevent_destroy_if_pages_exist
    return if pages.none?

    errors.add(:base, "нельзя удалить — есть страницы (#{pages.pluck(:uri).join(', ')}), ссылающиеся на этот объект")
    throw :abort
  end
end
