class PageTemplate < ActiveRecord::Base
  TEMPLATE_TYPES = %w[Profile List].freeze
  PAGEABLE_TYPES = %w[Entity Item Event Picture].freeze

  belongs_to :parent_page, class_name: "Page", foreign_key: :parent_page_id, optional: true

  # Вложенный List (см. PageTemplateGenerator class-comment): facet-
  # страницы этого template'а генерируются ПОД КАЖДОЙ страницей
  # parent_template, а не под одним статичным parent_page (тот тогда
  # игнорируется). Родитель обязательно тоже "List" — у не-List
  # template'а сгенерированные страницы не Page#list_objects-совместимы
  # (нет conditions), вкладываться под них нечем.
  belongs_to :parent_template, class_name: "PageTemplate", optional: true
  has_many :child_templates, class_name: "PageTemplate", foreign_key: :parent_template_id, dependent: :nullify

  # Доп. фильтр к template_conditions — если задан, объекты pageable_type
  # ещё и должны принадлежать этой Schema (с поддеревом, см.
  # PageTemplateGenerator). По умолчанию пустой — не фильтрует.
  #
  # Названа НЕ :schema — у page_templates уже есть свой текстовый столбец
  # "schema" (JSON-LD разметка, как у Page); belongs_to :schema перекрыл
  # бы его reader/writer своим (ждёт объект Schema, а не строку) —
  # ActiveRecord::AssociationTypeMismatch при сохранении формы.
  belongs_to :filter_schema, class_name: "Schema", foreign_key: :schema_id, optional: true

  # Сгенерированные по этому template страницы — Page#template_id (имя
  # колонки осталось template_id, не page_template_id, раз её так и
  # просили назвать раньше) — при удалении PageTemplate не удаляем их,
  # просто отвязываем.
  has_many :pages, foreign_key: :template_id, dependent: :nullify

  validates :lang, presence: true
  validates :template_type, inclusion: { in: TEMPLATE_TYPES }, allow_blank: true
  validates :pageable_type, inclusion: { in: PAGEABLE_TYPES }, allow_blank: true
  validate :parent_template_must_be_list_and_not_self

  def self.ransackable_attributes(auth_object = nil)
    %w[id active template_type pageable_type schema_id slug lang view layout page_ready page_published parent_template_id created_at updated_at]
  end

  # Пересобирает список так, чтобы вложенный template шёл сразу за
  # родительским (DFS), а не терялся где-то по алфавиту — в index иначе
  # непонятно, что один List "вложен" в другой (см. #parent_template).
  # list — уже отфильтрованный/отсортированный (ransack) массив — порядок
  # внутри одного уровня вложенности сохраняется.
  #
  # Родитель, отфильтрованный из list (не прошёл ransack-фильтр) — его
  # дети показываются как корни (иначе бы вообще пропали из списка).
  #
  # Возвращает [пересобранный_список, {id => глубина вложенности}].
  def self.tree_order(list)
    ids = list.map(&:id).to_set
    by_parent = list.group_by { |t| ids.include?(t.parent_template_id) ? t.parent_template_id : nil }

    ordered = []
    depths = {}

    walk = lambda do |parent_id, depth|
      (by_parent[parent_id] || []).each do |template|
        ordered << template
        depths[template.id] = depth
        walk.call(template.id, depth + 1)
      end
    end
    walk.call(nil, 0)

    [ordered, depths]
  end

  private

  def parent_template_must_be_list_and_not_self
    return if parent_template.blank?

    errors.add(:parent_template, "не может быть самим этим template") if parent_template_id == id
    errors.add(:parent_template, "должен быть типа List") unless parent_template.template_type == "List"
  end
end
