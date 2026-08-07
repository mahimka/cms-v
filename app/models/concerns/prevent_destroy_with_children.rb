# Без этого удаление родителя (Tag/Label) оставляет детей с
# parent_id/ancestry, указывающим в никуда — ровно то, что произошло
# и разломало /admin/tags, /admin/labels (краш при группировке).
# Тот же принцип, что и Pageable: не удалять каскадом, а не давать
# удалить, пока есть дочерние записи.
module PreventDestroyWithChildren
  extend ActiveSupport::Concern

  included do
    before_destroy :prevent_destroy_if_children_exist
  end

  private

  def prevent_destroy_if_children_exist
    return if children.none?

    errors.add(:base, "нельзя удалить — есть дочерние записи (#{children.pluck(:name).join(', ')}), сначала перепривяжите или удалите их")
    throw :abort
  end
end
