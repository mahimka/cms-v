class Routes < App

    get '/test-routes' do
      # erb :"/index", layout: :"/layout/layout" #, views: settings.views_default
     '/test-routes'
    end

    # .rss для списковых страниц (Page с conditions, например /beaches
    # или /de/beaches) — последние объекты списка с проставленным вручную
    # edited_at на их собственных детальных страницах.
    get '*.rss' do |uri|

      @page = Page.published.where(uri: uri).first

      pass unless @page
      pass unless @page.effective_conditions.present?

      @items = feed_items_for_list_page(@page)

      builder :'/feeds/list.rss', layout: false, views: settings.views
    end

    get '*' do |uri|

       @page = Page.published.where(uri: uri).first

       # ?page=N из query — запоминаем ДО того, как ветка ниже сама
       # положит туда номер страницы, разобранный из /N в uri (иначе
       # редирект старой схемы ниже примет свою же подстановку за
       # старую ссылку и зациклит /argentina/2 обратно в редирект на
       # /argentina/2).
       query_page = params[:page]

       # Пагинация списковых страниц — /argentina/2 вместо /argentina?page=2
       # (см. PaginateHelpers#paginate base_path:). Отдельного роута для
       # этого нет: /N мог бы быть и legit uri существующей страницы, так
       # что пробуем ТОЛЬКО когда буквального совпадения не нашлось, и
       # только если урезанный uri — действительно списковая страница
       # (effective_conditions present) — иначе /some-profile-page/2 не
       # должен тихо открывать страницу без /2 под чужим URL.
       if @page.nil? && uri =~ %r{\A(.+)/(\d+)\z}
         base_uri, page_num = $1, $2
         candidate = Page.published.where(uri: base_uri).first
         if candidate && candidate.effective_conditions.present?
           @page = candidate
           params[:page] = page_num
         end
       end

       # halt 404, "Not Found\n" unless @page
       pass unless @page

       # Старая схема пагинации — ?page=N в query, отдельно от uri (это
       # именно тот случай, когда @page нашёлся буквальным совпадением
       # uri, а не через /N-ветку выше: там path уже канонический). 301
       # на новую /N-схему — чтобы старые проиндексированные/сохранённые
       # ?page=2-ссылки не оставались рабочим, но дублирующим по контенту
       # альтернативным URL той же страницы.
       if query_page.present? && @page.effective_conditions.present?
         page_num = [query_page.to_i, 1].max
         canonical_uri = page_num > 1 ? "#{@page.uri}/#{page_num}" : @page.uri
         redirect canonical_uri, 301
       end

       # В старом проекте это собиралось из @base_page (мастер-страница
       # группы) — details/links/tags профильной страницы теперь живут
       # на Entity (page.pageable), а не на самой Page, так что @base_page
       # как отдельная переменная больше не нужен, entity его заменяет.
       entity = @page.pageable

       if entity
         # не у всех pageable-типов есть details/links (например у Ad их
         # нет) — вместо краша просто пусто.
         @page_details = entity.respond_to?(:details) ? (entity.details || {}) : {}
         @page_links   = entity.respond_to?(:links) ? entity.links.each_with_object({}) { |link, h| h[link.label&.name] = link.url } : {}
         @page_tags    = entity.tags.active.each_with_object({}) { |tag, h| h[tag.name] = tag.translation(@page.lang) }

         if entity.latitude && entity.longitude
           @closest_entities = Entity.generate_pages
             .where.not(id: entity.id)
             .where.not(latitude: nil, longitude: nil)
             .near([entity.latitude, entity.longitude], 50, units: :km, order: 'distance ASC')
             .limit(100)
         end
       end

       # Страница-список: conditions задаются только у мастера
       # (effective_conditions читает через него и у переводов).
       @objects = @page.list_objects if @page.effective_conditions.present?

       call_erb_view(@page.effective_view, layout: @page.effective_layout)

    end


end  