# app/models/page.rb

class Page < ActiveRecord::Base
  include Taggable

  has_ancestry

  TRANSLATABLE_FIELDS = %w[
    title
    h1
    body
    subtitle
    meta_description
  ].freeze

  # Эти поля заполняются только у основной страницы.
  MASTER_ONLY_FIELDS = %w[
    slug
    view
    layout
    pageable_type
    conditions
  ].freeze

  serialize :conditions, JSON

  belongs_to :master,
             class_name: "Page",
             optional: true,
             inverse_of: :translations

  has_many :translations,
           class_name: "Page",
           foreign_key: :master_id,
           inverse_of: :master,
           dependent: :destroy

  # я Claude (2026-08-02): записи History остаются даже после удаления
  # страницы (это лог редиректов), поэтому не destroy, а просто
  # отвязываем page_id.
  has_many :histories, dependent: :nullify

  scope :masters, -> { where(master_id: nil) }
  scope :translations_only, -> { where.not(master_id: nil) }
  scope :published, -> { where(published: true) }

  # URI не вводится вручную.
  # Он вычисляется перед каждой проверкой модели.
  before_validation :assign_calculated_uri

  # я Claude (2026-08-02): before_validation пересчитывает uri только
  # у самой сохраняемой записи. Если у master поменялся slug (или у
  # любой страницы поменялся uri из-за смены родителя), uri переводов
  # и дочерних страниц сам по себе не обновится — каскадно пересчитываем
  # его после сохранения.
  after_save :cascade_uri_to_descendants, if: :saved_change_to_uri?

  # я Claude (2026-08-02): если у опубликованной страницы поменялся uri,
  # старый адрес мог быть проиндексирован/расшарен — сохраняем редирект
  # со старого uri на новый в History.
  after_save :record_own_uri_history, if: -> { saved_change_to_uri? && published? }

  validates :lang,
            presence: true

  validates :uri,
            presence: true,
            uniqueness: true

  # У одной основной страницы может быть только один перевод
  # на конкретный язык.
  validates :lang,
            uniqueness: { scope: :master_id },
            if: :translation?

  # Slug обязателен только для некорневой основной страницы.
  validates :slug,
            presence: true,
            if: :non_root_master?

  validates :slug,
            format: {
              with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
              allow_blank: true,
              message: "может содержать только строчные латинские буквы, цифры и дефисы"
            },
            if: :master?

  validate :master_must_be_original_page
  validate :translation_language_must_differ
  validate :master_only_fields_must_be_empty_in_translation
  validate :translation_parent_must_match_master_parent

  # Основная страница имеет master_id = nil.
  def master?
    master_id.nil?
  end

  # Перевод имеет ссылку на основную страницу.
  def translation?
    master_id.present?
  end

  # Основная страница, из которой берутся общие параметры.
  def source_page
    master || self
  end

  # Основная страница, которая не является корнем дерева.
  def non_root_master?
    master? && parent.present?
  end

  # Общие параметры страницы.

  def effective_slug
    source_page.slug
  end

  def effective_view
    source_page.view
  end

  def effective_layout
    source_page.layout
  end

  def effective_pageable_type
    source_page.pageable_type
  end

  # conditions задаётся только у мастера (не зависит от языка) — переводы
  # берут его через мастера, аналогично effective_pageable_type.
  def effective_conditions
    source_page.conditions
  end

  # Страница-список: резолвит effective_conditions в реальную выборку
  # объектов через ListQuery.
  def list_objects
    ListQuery.new(effective_conditions).objects
  end

  # pageable_type — MASTER_ONLY_FIELDS (пустой у переводов), а pageable_id
  # задан и у мастера, и у переводов. Поэтому обычный полиморфный
  # belongs_to здесь не сработает на переводе (Rails возьмёт свой пустой
  # pageable_type) — тип берём через effective_pageable_type у мастера,
  # id — свой.
  def pageable
    return nil if pageable_id.blank?

    effective_pageable_type&.safe_constantize&.find_by(id: pageable_id)
  end

  # Основная страница и все её переводы.
  #
  # Работает как для основной страницы, так и для перевода.
  def language_versions
    source = source_page

    Page
      .where(id: source.id)
      .or(Page.where(master_id: source.id))
      .order(:lang)
  end

  # Только опубликованные версии.
  # Подходит для hreflang и переключателя языков.
  def published_language_versions
    language_versions.where(published: true)
  end

  def version_for(language)
    language_versions.find_by(lang: language.to_s)
  end

  # Цепочка для breadcrumbs, включая текущую страницу.
  def breadcrumbs
    ancestors.to_a + [self]
  end

  # Полный URI, рассчитанный из parent и slug.
  #
  # Основной корень:
  #   /
  #
  # Корень перевода:
  #   /it
  #
  # Обычная основная страница:
  #   /products/my-product
  #
  # Перевод:
  #   /it/products/my-product
  def calculated_uri
    return calculated_root_uri if parent.nil?

    join_uri(parent.uri, effective_slug)
  end

  private

  # Автоматически устанавливает URI до запуска validations.
  #
  # Благодаря этому при создании страницы поле uri может отсутствовать
  # в params и в форме.
  def assign_calculated_uri
    return if lang.blank?
    return if translation? && master.nil?
    return if parent.present? && effective_slug.blank?

    self.uri = calculated_uri
  end

  # URI корневой страницы.
  def calculated_root_uri
    master? ? "/" : "/#{lang}"
  end

  # Соединяет URI родителя и slug.
  def join_uri(parent_uri, slug)
    return "/#{slug}" if parent_uri == "/"

    "#{parent_uri}/#{slug}"
  end

  # я Claude (2026-08-02): cascade_uri_to_descendants и record_uri_history
  # вызываются друг у друга с явным получателем (dependent_page.xxx) для
  # соседних записей того же класса — такие методы в Ruby должны быть
  # protected, а не private, иначе вызов с явным получателем упадёт с
  # NoMethodError.
  protected

  # я Claude (2026-08-02): рекурсивно пересчитывает uri у прямых
  # переводов и дочерних страниц текущей страницы.
  #
  # uri перевода зависит от effective_slug (slug master-страницы),
  # uri дочерней страницы — от uri родителя, поэтому изменение uri
  # у self может затронуть обе связи. Пересохраняем через
  # update_column, чтобы не запускать повторно validations/callbacks,
  # и рекурсивно спускаемся дальше только туда, где uri реально
  # изменился — это же условие останавливает рекурсию.
  def cascade_uri_to_descendants
    (translations + children).each do |dependent_page|
      new_uri = dependent_page.calculated_uri

      next if dependent_page.uri == new_uri

      old_uri = dependent_page.uri

      dependent_page.update_column(:uri, new_uri)
      dependent_page.record_uri_history(old_uri, new_uri) if dependent_page.published?
      dependent_page.cascade_uri_to_descendants
    end
  end

  # я Claude (2026-08-02): сохраняет в History редирект со старого uri
  # на новый. old_uri уникален в таблице — если этот адрес уже был
  # источником редиректа раньше (например, uri туда-обратно менялся),
  # просто обновляем цель, а не плодим дубли.
  def record_uri_history(old_uri, new_uri)
    return if old_uri.blank? || old_uri == new_uri

    History
      .find_or_initialize_by(old_uri: old_uri)
      .update!(new_uri: new_uri, page: self)
  end

  private

  # Колбэк record_own_uri_history для сохранённой (self) страницы —
  # достаёт старое значение uri из dirty-трекинга Rails.
  def record_own_uri_history
    old_uri, new_uri = saved_change_to_uri

    record_uri_history(old_uri, new_uri)
  end

  # Перевод может ссылаться только непосредственно
  # на основную страницу.
  #
  # Запрещены цепочки:
  #
  #   German -> Italian -> English
  #
  # Разрешено:
  #
  #   Italian -> English
  #   German  -> English
  def master_must_be_original_page
    return if master.nil?
    return if master.master_id.nil?

    errors.add(
      :master,
      "должна быть основной страницей, а не переводом"
    )
  end

  # Нельзя создать перевод на том же языке,
  # что и основная страница.
  def translation_language_must_differ
    return unless translation?
    return if master.nil?
    return unless lang == master.lang

    errors.add(
      :lang,
      "должен отличаться от языка основной страницы"
    )
  end

  # Общие поля в переводах должны оставаться пустыми.
  #
  # slug, view, layout и pageable_type берутся из master.
  def master_only_fields_must_be_empty_in_translation
    return unless translation?

    MASTER_ONLY_FIELDS.each do |attribute|
      next if self[attribute].blank?

      errors.add(
        attribute,
        "можно задавать только у основной страницы"
      )
    end
  end

  # Родитель перевода должен быть переводом родителя
  # основной страницы на тот же язык.
  #
  # Например:
  #
  # master:
  #   /products/my-product
  #
  # Italian:
  #   /it/products/my-product
  #
  # Родителем итальянской страницы должен быть /it/products.
  def translation_parent_must_match_master_parent
    return unless translation?
    return if master.nil?

    # Перевод корневой основной страницы также является корнем.
    if master.parent.nil?
      if parent.present?
        errors.add(
          :parent,
          "должна отсутствовать у перевода корневой страницы"
        )
      end

      return
    end

    expected_parent =
      master.parent.translations.find_by(lang: lang)

    if expected_parent.nil?
      errors.add(
        :parent,
        "не найдена языковая версия родительской страницы"
      )

      return
    end

    return if parent_id == expected_parent.id

    errors.add(
      :parent,
      "должна соответствовать переводу родителя основной страницы"
    )
  end
end