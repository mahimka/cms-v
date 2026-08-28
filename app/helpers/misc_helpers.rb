module MiscHelpers

  # === start of view rendering helpers (project/views -> app/views с фолбэком) ===

  # helpers do
    def call_erb_view(view, layout: "default.erb")
      view = view.to_s
      layout = layout.to_s

      # 1. Поиск шаблона страницы (view): project/views -> app/views -> app/views/default.erb
      view_path = [
        (File.join(settings.views_project, view) unless view.empty?),
        (File.join(settings.views, view) unless view.empty?),
        File.join(settings.views, "default.erb")
      ].compact.find { |file| File.file?(file) }

      # 2. Поиск макета (layout): project/views/layout -> app/views/layout -> app/views/layout/default.erb
      layout_path = [
        (File.join(settings.views_project, "layout", layout) unless layout.empty?),
        (File.join(settings.views, "layout", layout) unless layout.empty?),
        File.join(settings.views, "layout", "default.erb")
      ].compact.find { |file| File.file?(file) }

      # Защита: если даже app/views/default.erb не существует
      unless view_path
        raise Errno::ENOENT, "Шаблон '#{view}' не найден ни в project/views, ни в app/views (включая default.erb)"
      end

      # 3. Передаем абсолютный путь БЕЗ расширения .erb как символ (Symbol)
      # Удаляем .erb с конца пути, так как Sinatra сама добавляет расширение
      view_sym = view_path.sub(/\.erb$/, '').to_sym

      if layout_path
        layout_sym = layout_path.sub(/\.erb$/, '').to_sym
        # Важно:views: "/" говорит Sinatra брать абсолютные пути от корня системы
        erb view_sym, layout: layout_sym, views: "/"
      else
        erb view_sym, layout: false, views: "/"
      end
    end

    def partial(partial_file, options = {})
      # Формируем список кандидатов на поиск
      # Порядок: project/views/partials/file.erb -> app/views/partials/file.erb
      partial_path = [
        File.join(settings.views_project, "partials", "#{partial_file}.erb"),
        File.join(settings.views, "partials", "#{partial_file}.erb")
      ].compact.find { |file| File.exist?(file) }

      # Если паршел не найден ни в одной из папок
      unless partial_path
        raise Errno::ENOENT, "Паршел '#{partial_file}' не найден ни в project/views/partials, ни в app/views/partials"
      end

      # Преобразуем абсолютный путь в символ без расширения .erb
      partial_sym = partial_path.sub(/\.erb$/, '').to_sym

      # Рендерим без layout и передаем локальные переменные
      erb partial_sym, layout: false, views: "/", locals: options
    end

    # Выводит переведённые названия тегов группы group_name, которыми
    # затегирован объект, привязанный к странице (page.pageable). По
    # умолчанию — только первый найденный тег группы, но можно вывести
    # несколько через limit. Каждый — в своей обёртке (как у tag_by_lang),
    # так что html_after так же работает построчным разделителем ("<br>").
    #
    # options:
    #   limit:      сколько тегов группы вывести максимум, по умолчанию 1
    #   css_class:  класс на обёртке, по умолчанию "tag is-light"
    #   html_tag:   тег обёртки, по умолчанию "span"
    #   html_after: что добавить после каждого тега
    #   page:       чья страница — по умолчанию текущая @page
    def tags_by_group(group_name, options = {})
      limit      = options[:limit]      || 1
      css_class  = options[:css_class]  || "tag is-light"
      html_tag   = options[:html_tag]   || "span"
      html_after = options[:html_after] || ""
      page       = options[:page]       || @page

      return "" unless page&.pageable

      group = Tag.find_by(name: group_name)
      return "" unless group

      matching_tags = page.pageable.tags.select { |t| t.parent_id == group.id }.first(limit)

      matching_tags.map do |tag|
        "<#{html_tag} class='#{css_class}'>#{tag.translation(page.lang)}</#{html_tag}>#{html_after}"
      end.join
    end



    # Выводит переведённое название тега tag_name, если объекту, привязанному
    # к странице (page.pageable), он присвоен. Иначе — "".
    #
    # options:
    #   css_class:  класс на обёртке, по умолчанию "tag is-light"
    #   html_tag:   тег обёртки, по умолчанию "span"
    #   html_after: что добавить после закрывающего тега
    #   page:       чья страница — по умолчанию текущая @page; передавать
    #               явно при рендере списка/карточек, где для каждой строки
    #               нужна её собственная page
    def tag_by_lang(tag_name, options = {})
      css_class  = options[:css_class]  || "tag is-light"
      html_tag   = options[:html_tag]   || "span"
      html_after = options[:html_after] || ""
      page       = options[:page]       || @page

      return "" unless page&.pageable

      tag = page.pageable.tags.find { |t| t.name == tag_name }
      return "" unless tag

      translated = tag.translation(page.lang)

      "<#{html_tag} class='#{css_class}'>#{translated}</#{html_tag}>#{html_after}"
    end


    # Выводит переведённое название label и значение детали label_name у
    # объекта, привязанного к странице (page.pageable). Если такой детали
    # нет (или значение пустое) — "".
    #
    # options:
    #   separator:  чем разделить название и значение, по умолчанию ": "
    #   css_class:  класс на обёртке, по умолчанию "tag is-light"
    #   html_tag:   тег обёртки, по умолчанию "span"
    #   html_after: что добавить после закрывающего тега
    #   page:       чья страница — по умолчанию текущая @page
    def detail_by_label(label_name, options = {})
      separator  = options[:separator]  || ": "
      css_class  = options[:css_class]  || "tag is-light"
      html_tag   = options[:html_tag]   || "span"
      html_after = options[:html_after] || ""
      page       = options[:page]       || @page
      only_value = options[:only_value] || false

      return "" unless page&.pageable

      value = page.pageable.details[label_name]
      return "" if value.blank?

      label = Label.find_by(name: label_name)
      translated_label = label ? label.translation(page.lang) : label_name

      if only_value
        "#{value}"
      else
        "<#{html_tag} class='#{css_class}'>#{translated_label}#{separator}#{value}</#{html_tag}>#{html_after}"
      end
    end




    # # Тег в HTML, если он есть в page_tags (по умолчанию — @page_tags
    # # текущей страницы), иначе пустая строка. page_tags — произвольный
    # # hash { tag_name => переведённое_значение }, поэтому подходит и для
    # # тегов текущей @page, и для тегов сущности из цикла (см. _card_room.erb).
    # def tag_by_lang(tag_name, options = {})
    #   css_class  = options[:css_class]  || "tag is-light"
    #   html_tag   = options[:html_tag]   || "span"
    #   html_after = options[:html_after] || ""
    #   page_tags  = options[:page_tags]  || @page_tags || {}

    #   translated = page_tags[tag_name]

    #   return "" unless translated

    #   "<#{html_tag} class='#{css_class}'>#{translated}</#{html_tag}>#{html_after}"
    # end

    # UI-строка по ключу label_name (например '_faq', 'season_low') на
    # язык lang. Label#translation сам фолбэчит на label.name, если для
    # lang нет перевода — здесь остаётся обработать только случай, когда
    # такого Label вообще нет в базе.
    def label_by_lang(label_name, lang = @page&.lang)
      label = Label.find_by(name: label_name)

      return label_name unless label

      label.translation(lang)
    end

    # Тот же ListQuery, что у Page#list_objects, но без страницы вообще —
    # для инлайн-подборок прямо в контенте.
    #
    #   objects_matching('Entity', ["and", "Hotel", "Izola"])
    #   objects_matching('Event', ["or", "Concert", "Festival"], start_at: Time.current.iso8601)
    def objects_matching(object_type, tags_expression = nil, **extra_conditions)
      conditions = { "object" => object_type }
      conditions["tags"] = tags_expression if tags_expression
      extra_conditions.each { |key, value| conditions[key.to_s] = value }

      ListQuery.new(conditions).objects
    end
  # end

  # === end of view rendering helpers ===


  def link_to(schema_id, options={})
    anchor_text   = options[:anchor_text] || ''
    anchor_column = options[:anchor_column] || 'anchor_1' #h1
    lang          = options[:lang] || @page.lang
    css_class     = options[:css_class] || ''
    title         = options[:title] || 'title'
    
    begin
      # schema_id — uri мастер-страницы (например '/rooms/1', всегда lang
      # мастера, обычно sl), НЕ конкретной языковой версии — искать нужно
      # по нему одному, а на нужный язык переключает version_for ниже.
      # find_by_..._and_lang требовал uri и lang сразу, а у uri уже свой
      # lang — из-за этого на любой не-sl странице всегда получали nil.
      page = Page.find_by(id: schema_id) if schema_id.is_a? Integer
      page = Page.find_by(uri: schema_id) if schema_id.is_a? String

      page = page&.version_for(lang)

      if page
        if anchor_text.blank?
          anchor = page.send(anchor_column) 
        else
          anchor = anchor_text 
        end

        "<a href='#{page.uri}' class='#{css_class} is-underlined' title='#{title}'>#{anchor}</a>"

      else
        "<!--page is not found-->"
      end

    rescue => e

      return '!! some error in link_to !!'

    end

  end

  # Рейтинг звёздочками через SVG-иконку Lucide (у Bulma нет своего
  # star-rating компонента — только CSS, без иконок). Заливка — не
  # целая/половинчатая, а точный процент на каждую звезду (через overlay
  # с clip по ширине), поэтому 3.7 честно покажет почти-заполненную
  # четвёртую звезду, а не округление до половины.
  STAR_RATING_SVG_PATH = 'M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z'.freeze

  def star_rating(rating, max: 5, size: 16, color: '#f5a623', empty_color: '#dbdbdb')
    return '' if rating.nil?

    rating = rating.to_f.clamp(0, max)

    stars = (1..max).map do |i|
      fill_percent = ((rating - (i - 1)).clamp(0, 1) * 100).round(1)

      <<~HTML
        <span style="position:relative; display:inline-block; width:#{size}px; height:#{size}px; vertical-align:middle;">
          <svg xmlns="http://www.w3.org/2000/svg" width="#{size}" height="#{size}" viewBox="0 0 24 24" fill="none" stroke="#{empty_color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="position:absolute; top:0; left:0;"><path d="#{STAR_RATING_SVG_PATH}"/></svg>
          <span style="position:absolute; top:0; left:0; width:#{fill_percent}%; height:100%; overflow:hidden; white-space:nowrap;">
            <svg xmlns="http://www.w3.org/2000/svg" width="#{size}" height="#{size}" viewBox="0 0 24 24" fill="#{color}" stroke="#{color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="#{STAR_RATING_SVG_PATH}"/></svg>
          </span>
        </span>
      HTML
    end.join

    "<span class=\"star-rating\" title=\"#{rating}/#{max}\">#{stars}</span>"
  end

end