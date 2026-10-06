module PageTreeHelpers

  DEFAULT_TREE_PAGEABLE_LIMIT = 50

  # Строки одного уровня дерева: дети parent, либо корни при parent == nil.
  #
  # Порядок: 1) обычные страницы, 2) страницы-списки (effective_conditions),
  # 3) pageable-страницы — не более tree_pageable_limit (лимит и порядок
  # считает БД, остальные сворачиваются в ссылку "more" на отфильтрованный
  # /admin/pages). Внутри уровня — по uri; корни — основной сайт, затем
  # языки в порядке settings.languages (sort_root_pages).
  #
  # Возвращает { rows: [{page:, has_children:}, ...], more: {count:, url:} | nil }
  def prepare_tree_rows(parent = nil)
    scope = parent ? parent.children.order(:uri) : Page.roots
    pageable_scope = scope.where.not(pageable_id: nil)

    # master подгружаем заранее: effective_conditions у перевода берёт
    # conditions мастера (source_page) — иначе по запросу на каждый перевод.
    regular_pages = scope.where(pageable_id: nil).includes(:master).to_a
    regular_pages = sort_root_pages(regular_pages) if parent.nil?
    lists, plain = regular_pages.partition { |page| page.effective_conditions.present? }

    visible = pageable_scope.limit(tree_pageable_limit).to_a
    hidden_count = pageable_scope.count - visible.length

    pages = plain + lists + visible

    # один запрос на весь уровень вместо page.children.exists? для каждой строки
    parents_with_children = Page.where(ancestry: pages.map(&:child_ancestry)).distinct.pluck(:ancestry).to_set

    rows = pages.map { |page| { page: page, has_children: parents_with_children.include?(page.child_ancestry) } }
    more = { count: hidden_count, url: tree_more_pageable_url(parent) } if hidden_count.positive?

    { rows: rows, more: more }
  end

  # Ограничение на количество pageable-страниц, показываемых в дереве
  # на одном уровне. Настраивается через settings.limit_tree_pageable,
  # по умолчанию — DEFAULT_TREE_PAGEABLE_LIMIT.
  def tree_pageable_limit
    value = settings.respond_to?(:limit_tree_pageable) ? settings.limit_tree_pageable.to_i : 0

    value.positive? ? value : DEFAULT_TREE_PAGEABLE_LIMIT
  end

  # 'p' — у страницы задан pageable, 'l' — заданы conditions (список),
  # 't' — страница создана по PageTemplate, nil — обычная страница.
  def tree_type_letter(page)
    return "p" if page.pageable_id.present?
    return "l" if page.effective_conditions.present?
    return "t" if page.template_id.to_i.positive?

    nil
  end

  # Подпись узла: у корней — uri, у остальных — "/slug". У переводов slug
  # пустой (его хранит мастер), поэтому берём последний сегмент uri.
  def tree_label(page)
    return page.uri if page.root?

    "/" + (page.slug.presence || page.effective_slug.presence || page.uri.to_s.chomp("/").split("/").last.to_s)
  end

  # Кнопка "перевести поле через Gemini" рядом с полем в форме страницы.
  #
  # На мастер-странице (у которой уже есть хотя бы один перевод) — берёт
  # значение поля у самого мастера и обновляет его во ВСЕХ переводах.
  # На странице перевода — берёт значение того же поля у её мастера и
  # переводит только в неё саму (обновить/пересобрать этот конкретный
  # перевод после правки мастера).
  #
  # Пустая строка (ничего не рендерится), если поле не входит в
  # Page::TRANSLATABLE_FIELDS, нечего переводить (исходный текст пуст),
  # или у мастера ещё нет ни одного перевода.
  def translate_field_button(page, field)
    field = field.to_s
    return "" unless Page::TRANSLATABLE_FIELDS.include?(field)

    if page.master?
      return "" unless Page.exists?(master_id: page.id)

      source_text = page[field]
      tooltip = "Перевести #{field} и обновить во всех переводах"
    else
      source_text = page.master&.[](field)
      tooltip = "Перевести #{field} из мастера в этот перевод"
    end

    return "" if source_text.blank?

    <<~HTML
      <button type="button" class="button is-small is-info is-light py-0 px-1"
        data-page-translate-field data-field="#{field}" data-source-page-id="#{page.id}"
        title="#{Rack::Utils.escape_html(tooltip)}">✨</button>
    HTML
  end

  # Замочек рядом с полем, отредактированным вручную на странице,
  # сгенерированной по PageTemplate — клик снимает защиту (Page#
  # unmark_edited_field!), чтобы следующий force refresh снова мог
  # перезаписать это поле. Пусто (ничего не рендерится), если страница
  # не по template, поле не защищаемое, или прямо сейчас не защищено —
  # замочек показываем только когда есть что снимать.
  def page_field_lock(page, field)
    field = field.to_s
    return "" if page.template_id.blank?
    return "" unless Page::PROTECTABLE_FIELDS.include?(field)
    return "" unless page.edited_field?(field)

    button_id = "unlock_field_#{page.id}_#{field}"

    # НЕ <form> — этот хелпер вставляется внутри большой формы
    # редактирования страницы (_tree_edit_form.erb), а вложенные <form>
    # невалидны в HTML: браузер обрывает внешнюю форму раньше времени
    # (см. историю с PageTemplate, тот же класс бага). Вместо формы —
    # обычная кнопка + голый $.ajax GET, как у delete_in_place/
    # checkbox_in_place в in_place_editing_helpers.rb.
    <<~HTML
      <button type="button" id="#{button_id}" class="button is-small is-warning is-light py-0 px-1"
        title="Поле отредактировано вручную — защищено от force refresh шаблона. Клик снимет защиту.">🔒</button>
      <script>
        $(document).ready(function(){
          $("##{button_id}").click(function(){
            if (!confirm('Снять защиту с поля #{field}? Следующий force refresh шаблона сможет его перезаписать.')) return;
            $.ajax({url: "/admin/pages/#{page.id}/unlock_field?field=#{field}", success: function(result){
              $("##{button_id}").fadeOut(300);
            }});
          });
        });
      </script>
    HTML
  end

  # Ссылка на форму редактирования объекта, к которому привязана
  # detail-страница (Page#pageable) — у каждого pageable_type своя
  # админка: у Entity есть отдельная edit_in_place-форма, у Item/Event —
  # только обычный edit (свои edit_in_place для них ещё не делали).
  # nil, если у страницы нет pageable (обычная/List-страница).
  def pageable_edit_url(page)
    return nil if page.pageable_id.blank?

    case page.effective_pageable_type
    when "Entity" then "/admin/entities/#{page.pageable_id}/edit_in_place"
    when "Item" then "/admin/items/#{page.pageable_id}/edit"
    when "Event" then "/admin/events/#{page.pageable_id}/edit"
    end
  end

  private

  # Ссылка на /admin/pages с фильтром по родителю (или его отсутствию)
  # и по наличию pageable — чтобы увидеть все сиблинги, не поместившиеся
  # в дерево из-за лимита.
  def tree_more_pageable_url(parent)
    q = { "pageable_id_not_null" => "1" }

    if parent
      q["ancestry_eq"] = parent.child_ancestry
    else
      q["ancestry_null"] = "1"
    end

    "/admin/pages?" + Rack::Utils.build_nested_query("q" => q)
  end

end
