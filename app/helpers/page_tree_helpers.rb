module PageTreeHelpers

  DEFAULT_TREE_PAGEABLE_LIMIT = 50

  # Готовит строки дерева для одного уровня (дети одного родителя,
  # либо корневые страницы).
  #
  # Порядок вывода:
  #   1. страницы без conditions и без pageable — по алфавиту
  #   2. страницы с заданными conditions — по алфавиту
  #   3. страницы с заданным pageable — не более tree_pageable_limit,
  #      дальше — ссылка "more" на отфильтрованный список в /admin/pages
  #
  # Внутри каждой группы сохраняется порядок, в котором страницы
  # переданы в pages (ожидается — уже отсортированные по алфавиту).
  #
  # Возвращает { rows: [{page:, has_children:}, ...], more: {count:, url:} | nil,
  #   nested: true|false } — nested: true, когда это дочерний уровень
  #   (parent задан), а не корень дерева — _tree_nodes.erb рисует по
  #   нему "↳" у каждой строки: одного отступа/вертикальной линии от
  #   ::before было визуально недостаточно, чтобы было сразу понятно,
  #   что раскрытые после клика "+" строки — вложенные, а не соседние.
  def prepare_tree_rows(pages, parent: nil)
    no_group    = []
    list_group  = []
    pageable_group = []

    pages.each do |page|
      if page.effective_conditions.present?
        list_group << page
      elsif page.pageable_id.present?
        pageable_group << page
      else
        no_group << page
      end
    end

    limit = tree_pageable_limit
    visible_pageable = pageable_group.first(limit)
    hidden_pageable_count = pageable_group.length - visible_pageable.length

    ordered_pages = no_group + list_group + visible_pageable

    rows = ordered_pages.map do |page|
      { page: page, has_children: page.children.exists? }
    end

    more =
      if hidden_pageable_count.positive?
        { count: hidden_pageable_count, url: tree_more_pageable_url(parent) }
      end

    { rows: rows, more: more, nested: parent.present? }
  end

  # Ограничение на количество pageable-страниц, показываемых в дереве
  # на одном уровне. Настраивается через settings.limit_tree_pageable,
  # по умолчанию — DEFAULT_TREE_PAGEABLE_LIMIT.
  def tree_pageable_limit
    value = settings.respond_to?(:limit_tree_pageable) ? settings.limit_tree_pageable.to_i : 0

    value.positive? ? value : DEFAULT_TREE_PAGEABLE_LIMIT
  end

  # 'p' — у страницы задан pageable, 'l' — заданы conditions (список),
  # nil — обычная страница.
  def tree_type_letter(page)
    return "p" if page.pageable_id.present?
    return "l" if page.effective_conditions.present?

    nil
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
