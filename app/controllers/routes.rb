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

       # halt 404, "Not Found\n" unless @page
       pass unless @page

       # В старом проекте это собиралось из @base_page (мастер-страница
       # группы) — details/links/tags профильной страницы теперь живут
       # на Entity (page.pageable), а не на самой Page, так что @base_page
       # как отдельная переменная больше не нужен, entity его заменяет.
       entity = @page.pageable

       if entity
         @page_details = entity.details || {}
         @page_links   = entity.links.each_with_object({}) { |link, h| h[link.label&.name] = link.url }
         @page_tags    = entity.tags.active.each_with_object({}) { |tag, h| h[tag.name] = tag.translation(@page.lang) }

         if entity.latitude && entity.longitude
           @closest_entities = Entity.active
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