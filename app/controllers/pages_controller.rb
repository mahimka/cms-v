class PagesController < App


  # def syncronize_children_pages 

  #   if @page.saved_change_to_ancestry
  #     @new_base_parent = @page.parent
  #   end


  #   sub_pages = @page.sublangs
  #   puts 'dddd++++++++++++++++++++++++++++++++++++++++++++++++++++++'
  #   puts sub_pages.length
  #   puts 'dddd++++++++++++++++++++++++++++++++++++++++++++++++++++++'

  #   puts params[:page]

  #   params_to_sync = {}
  #   params_to_sync[:category] = params[:page][:category]
  #   params_to_sync[:item_id] = params[:page][:item_id]
  #   params_to_sync[:layout] = params[:page][:layout]
  #   params_to_sync[:view] = params[:page][:view]
  #   params_to_sync[:list_partial] = params[:page][:list_partial]
  #   params_to_sync[:has_feed] = params[:page][:has_feed]
  #   params_to_sync[:is_top] = params[:page][:is_top]
  #   params_to_sync[:schema_id] = params[:page][:schema_id]
  #   # params_to_sync[:ancestry] = params[:page][:ancestry]

  #   puts '+++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    
  #   sub_pages.each do |sub_page|
  #     unless @history_created.blank?
  #       folder = settings.languages[sub_page.lang.to_sym][:folder]
  #       puts 'folder ' + folder
  #       puts folder + params[:url_original]
  #       # params_to_sync[:url] = folder + params[:page][:url]
  #       History.find_or_create_by!(url: folder + params[:url_original], page_id: sub_page.id)

  #       params_to_sync[:url] = folder + params[:page][:url]
  #     end

  
  #     if @page.saved_change_to_ancestry?
  #       new_lang_parent = Page.where(lang: sub_page.lang, lang_ref: @new_base_parent.lang_ref).first

  #       if new_lang_parent.ancestry
  #         params_to_sync[:ancestry] = new_lang_parent.ancestry + '/' + new_lang_parent.id.to_s

  #       else
  #         params_to_sync[:ancestry] = new_lang_parent.id.to_s

  #       end

  #       # halt 200, "@page.saved_change_to_ancestry: #{@page.saved_change_to_ancestry} new parent: #{@page.parent.id}, new_lang_parent: #{new_lang_parent.id}, new_anc: #{new_lang_parent.ancestry + '/' + new_lang_parent.id.to_s}"

  #        # Код выполнится, только если ancestry изменилось
  #     end   


  #     puts
  #     puts 'params to sync _______________________________'
  #     puts params_to_sync
  #     sub_page.update(params_to_sync)
  #   end

  # end

  namespace '/admin' do 

    # index 
    get '/pages' do 

      @q = Page.ransack(params[:q])
      @pages_found = @q.result(distinct: true) # for index.rb
      @pages       = @q.result(distinct: true).page(params[:page]).per(100)

      erb :"/pages/index", layout: :"/layout/wide", views: settings.views_admin

    end  

    get '/pages/:id/edit-in-place' do 

      @page = Page.find(params[:id])
      erb :"pages/edit_in_place", layout: :"/layout/wide", views: settings.views_admin

    end



     post '/pages/setup-root' do
      if Page.exists?(uri: "/", master_id: nil)
        halt 409, "Корневая страница уже существует"
      end

      root_page = Page.new(
        uri: "/",
        lang: settings.home_language,
        master_id: nil,
        parent_id: nil,
        slug: nil,
        title: "Home",
        h1: "Home",
        published: false
      )

      if root_page.save
        redirect "/admin/pages/tree"
      else
        halt 422, root_page.errors.full_messages.join(", ")
      end
    end


    # форма новой страницы из обысного списка, не из дерева!!!

    get '/pages/new' do
      @parent_pages = Page
        .where(master_id: nil)
        .order(:uri)

      @page = Page.new(lang: settings.home_language)

      if params[:pageable_type].present? && params[:pageable_id].present?
        assign_pageable_defaults(@page, params[:pageable_type], params[:pageable_id])
        @parent_pages = Page.selectable_as_pageable_parent.order(:uri)

      elsif params[:source_page_id].present?
        source_page = Page.masters.find(params[:source_page_id])

        if params[:sub] == 'true'
          # Новая пустая дочерняя страница.
          # Из исходной страницы берём только parent.
          @page.parent = source_page

        elsif params[:copy] == 'true'
          # Новая страница с данными исходной страницы.
          @page = source_page.dup

          # Это самостоятельная master-страница.
          @page.lang      = settings.home_language
          @page.master_id = nil

          # Оставляем того же родителя, что был у исходной страницы.
          @page.parent = source_page.parent

          # Slug должен быть изменён пользователем,
          # иначе получится тот же uri.
          @page.slug = nil

          # URI модель рассчитает заново перед validation.
          @page.uri = nil

          # Новая копия по умолчанию не опубликована.
          @page.published = false
          @page.edited_at = nil
        
        elsif !params[:lang].blank? 
          @page = source_page.dup
          @page.lang      = params[:lang]
          @page.master_id = source_page.id
          @page.published = false
          @page.edited_at = nil

        end
      end

      erb :"/pages/_tree_new_form",
          layout: :"/layout/wide",
          views: settings.views_admin
    end


    # Форма новой страницы внутри дерева.
    #
    # Варианты:
    #   /pages/new/form
    #   /pages/new/form?source_page_id=5&sub=true
    #   /pages/new/form?source_page_id=5&copy=true
    get '/pages/new/form' do
      source_page =
        Page.masters.find_by(id: params[:source_page_id])

      @page =
        if source_page && params[:copy] == 'true'
          source_page.dup.tap do |page|
            # Копия становится новой самостоятельной master-страницей.
            page.lang = settings.home_language
            page.master_id = nil

            # Новый slug пользователь задаёт сам.
            page.slug = nil

            # URI пересчитает модель.
            page.uri = nil

            # По умолчанию копия не опубликована.
            page.published = false
            page.edited_at = nil

            # Копия остаётся рядом с исходной страницей.
            page.parent = source_page.parent
          end
        else
          Page.new(lang: settings.home_language)
        end

      # Новая пустая подстраница.
      if source_page && params[:sub] == 'true'
        @page.parent = source_page
      end

      # Новый перевод исходной master-страницы.
      if source_page && params[:lang].present?
        @page = source_page.dup

        @page.lang      = params[:lang]
        @page.master_id = source_page.id
        @page.published = false
        @page.edited_at = nil

        # slug/view/layout/pageable_type задаются только у master-страницы.
        Page::MASTER_ONLY_FIELDS.each { |field| @page[field] = nil }

        # Родитель перевода — перевод родителя master-страницы
        # на тот же язык (см. Page#translation_parent_must_match_master_parent).
        @page.parent =
          if source_page.parent.nil?
            nil
          else
            source_page.parent.translations.find_by(lang: params[:lang])
          end
      end

      @parent_pages = Page.masters.order(:uri)

      erb :"/pages/_tree_new_form",
          layout: false,
          views: settings.views_admin
    end


    # Создание новой страницы - различает обычные запрос и AJAX
    post '/pages' do
      page_params, conditions_error = normalize_page_conditions(params[:page])
      @page = Page.new(page_params)

      # Перевод присылает свои lang/master_id скрытыми полями формы.
      # Обычная master-страница — всегда домашний язык и без master.
      if @page.master_id.blank?
        @page.lang = settings.home_language
        @page.master_id = nil
      end

      if conditions_error.nil? && @page.save
        if request.xhr?
          headers "X-Page-Id" => @page.id.to_s
          status 201
          body ""
        else
          redirect "/admin/pages"
        end
      else
        @page.errors.add(:conditions, conditions_error) if conditions_error

        @parent_pages =
          if @page.pageable_id.present?
            Page.selectable_as_pageable_parent.order(:uri)
          else
            Page.masters.order(:uri)
          end

        if request.xhr?
          status 422

          erb :"/pages/_tree_new_form",
              layout: false,
              views: settings.views_admin
        else
          erb :"/pages/_tree_new_form",
              layout: :"/layout/wide",
              views: settings.views_admin
        end
      end
    end

    patch '/pages/:id' do
      @page = Page.find(params[:id])
      page_params, conditions_error = normalize_page_conditions(params[:page])

      if conditions_error.nil? && @page.update(page_params)
        if request.xhr?
          headers "X-Page-Id" => @page.id.to_s
          status 200
          body ""
        else
          redirect "/admin/pages"
        end
      else
        @page.assign_attributes(page_params.except("conditions")) if conditions_error
        @page.errors.add(:conditions, conditions_error) if conditions_error
        @parent_pages = Page
          .where.not(id: @page.id)
          .order(:lang, :uri)

        if request.xhr?
          status 422

          erb :"/pages/_tree_edit_form",
              layout: false,
              views: settings.views_admin
        else
          status 422

          erb :"/pages/edit",
              layout: :"/layout/wide",
              views: settings.views_admin
        end
      end
    end


    get '/pages/:id/edit/form' do
      @page = Page.find(params[:id])
      @parent_pages = Page.where.not(id: @page.id).order(:lang, :uri)

      erb :"/pages/edit",
          layout: false,
          views: settings.views_admin
    end    




    # ============== делаем tree по chatGPT ========================================

    # Страница с деревом и правой панелью
    get '/pages/tree' do
      root_pages = sort_root_pages(Page.roots.to_a)
      @tree_rows = prepare_tree_rows(root_pages, parent: nil)

      erb :"/pages/tree",
          layout: :"/layout/wide",
          views: settings.views_admin
    end

    get '/pages/:id/children' do
      parent = Page.find(params[:id])
      pages = parent.children.order(:uri).to_a

      @tree_rows = prepare_tree_rows(pages, parent: parent)

      erb :"/pages/_tree_nodes",
          layout: false,
          views: settings.views_admin
    end

    # Загружает форму страницы в правую панель
    get '/pages/:id/form' do
      @page = Page.find(params[:id])

      @parent_pages = Page
        .masters
        .where.not(id: @page.id)
        .order(:uri)

      erb :"/pages/_tree_edit_form",
          layout: false,
          views: settings.views_admin
    end

    # Поиск страниц по h1 для @@-автокомплита в body/faq (см. pages-tree.js) —
    # ищем в языке редактируемой страницы, чтобы найденный uri был сразу
    # в нужном языке (link_to всё равно резолвит через version_for, но так
    # результаты в списке понятнее автору).
    get '/pages/search_by_h1' do
      content_type :json

      query = params[:q].to_s.strip
      lang  = params[:lang].presence || settings.home_language

      halt 200, [].to_json if query.blank?

      pages = Page
        .where(lang: lang)
        .where("h1 LIKE ? ESCAPE '\\'", "%#{Page.sanitize_sql_like(query)}%")
        .where.not(h1: [nil, ""])
        .order(:h1)
        .limit(10)

      pages.map { |page| { uri: page.uri, h1: page.h1 } }.to_json
    end

    # для содержимого дерева
    get '/pages/tree/nodes' do
      root_pages = sort_root_pages(Page.roots.to_a)
      @tree_rows = prepare_tree_rows(root_pages, parent: nil)

      erb :"/pages/_tree",
          layout: false,
          views: settings.views_admin
    end

    # ============== конец tree по chatGPT ========================================

  end

    # get '/pages/tree' do 
    #   @q = Page.ransack(params[:q])
    #   erb :"/pages/tree", layout: :"/layout/wide", views: settings.views_admin
    # end  

    # # tree - for ajax calls
    # get '/pages/find_children' do 
    #   # protected!
    #   pages = Page.find(params[:page_id]).children.order("is_top DESC").order("position ASC") #.select(:id, :category, :ancestry, :url, :template_id, :active, :position, :is_top).limit(100)
    #   #pages = root_page.children.order("is_top DESC").order("position ASC")
    #   pages_tree(pages, 0, params[:page_id])
    # end 

    # edit - ajax (in tree)
    # get '/pages/:id/edit_ajax' do 
    #   # protected!
    #   @page = Page.find_by_id(params[:id])
    #   # для Hash нет метода unshift, поэтомУ:
    #   #https://stackoverflow.com/questions/20758818/insert-element-at-the-beginning-of-ruby-hash
    #   #@template_list_values = {"": ""}.merge(Template.where(kind: "pageable").to_h {|template| [template.id, template.url + " - " + template.id.to_s]})

    #   erb :"pages/edit_for_tree", :layout => false, views: settings.views_admin #:'/layout_wide'
    # end   

    # edit - ajax tags and links (in tree)
    # get '/pages/:id/edit_page_tags_and_links' do 
    #   # protected!
    #   @page = Page.find_by_id(params[:id])
    #   # для Hash нет метода unshift, поэтомУ:
    #   #https://stackoverflow.com/questions/20758818/insert-element-at-the-beginning-of-ruby-hash
    #   #@template_list_values = {"": ""}.merge(Template.where(kind: "pageable").to_h {|template| [template.id, template.url + " - " + template.id.to_s]})

    #   erb :"pages/edit_for_tree_tags_and_links", :layout => false, views: settings.views_admin #:'/layout_wide'
    # end  


    # edit - ajax tags and links (in tree)
    # get '/pages/:id/edit_page_pictures' do 
    #   # protected!
    #   @page = Page.find_by_id(params[:id])
    #   # для Hash нет метода unshift, поэтомУ:
    #   #https://stackoverflow.com/questions/20758818/insert-element-at-the-beginning-of-ruby-hash
    #   #@template_list_values = {"": ""}.merge(Template.where(kind: "pageable").to_h {|template| [template.id, template.url + " - " + template.id.to_s]})

    #   erb :"pages/edit_for_tree_pictures", :layout => false, views: settings.views_admin #:'/layout_wide'
    # end  


  #ajax
  # get '/pages/:page_id/edit' do 

  #   @page = Page.find(params[:page_id])
  #   @page.url
  #   erb :"pages/edit_in_place", layout: :"/layout/wide", views: settings.views_admin

  # end


  # update - ajax 
  # patch '/pages/:id/ajax' do
  #   # protected!
  #   @page = Page.find_by_id(params[:id])

  #   # check if changed https://stackoverflow.com/questions/21297506/update-attributes-for-user-only-if-attributes-have-changed
  #   @page.assign_attributes(params[:page])

  #   # # Проверяем, изменилось ли конкретное поле ancestry
  #   # if @page.ancestry_changed?
  #   #   @page.ancestry_changed? — возвращает true, если значение изменилось.
  #   #   @page.ancestry_was — возвращает старое значение поля, которое сейчас сохранено в базе данных.
  #   #   @page.ancestry_change — возвращает массив из двух элементов: [старое_значение, новое_значение]. Например: ["1/2", "1/2/5"]. Если изменений не было, вернет nil.
  #   #         # Логика, если ancestry изменилось
  #   #   puts "Поле ancestry изменилось!"
  #   # end
    
  #   if @page.changed?
       
  #      if @page.save!

  #        @history_created = "" 

  #        if params[:url_original] != params[:page][:url] #&& !!!!!!!!!!!!!!!!!!!!! status published!!!
  #          History.find_or_create_by(url: params[:url_original], page_id: @page.id)
  #          @history_created = "<br>" + " History created!"
  #        end  

         
  #        syncronize_children_pages



  #        notice =  "<div class='content'>"
  #        notice += "  <div class='notification is-success'>"
  #        notice += "    <button class='delete'></button>"
  #        notice += "    Page updated!"
  #        notice += @history_created
  #        notice += "  </div>"
  #        notice += "</div>"
  #        notice += "<br>"


  #      else

  #        notice =  "<div class='content'>"
  #        notice += "  <div class='notification is-danger'>"
  #        notice += "    <button class='delete'></button>"
  #        notice += "    <p >Cannot update the page:</p>"
  #        notice += "    <ol>" 
  #        @page.errors.full_messages.each do |msg|
  #           notice += "<li>" + msg
  #        end 
  #        notice += "    </ol>" 
  #        notice += "  </div>"
  #        notice += "</div>"
  #        notice += "<br>"

  #      end  
     
  #   else
  #        notice =  "<div class='content'>"
  #        notice += "  <div class='notification is-warning'>"
  #        notice += "    <button class='delete'></button>"
  #        notice += "    Nothing was hanged!"
  #        notice += "  </div>"
  #        notice += "</div>"
  #        notice += "<br>"

  #   end 

  #   notice

  # end  


  # copy, copy to subpage
  # get '/pages/:id/copy' do 
  #   # protected!
  #   @source = Page.find(params[:id])
  #   @page = @source.dup 
  #   @page.parent_id = @source.id if params[:to_subpage]

  #   @page.ready = false
  #   @page.published = false
    
  #   if params[:ajax]
  #     @info = "You are coping from existing page!"
  #     @info = "You are coping to SUBPAGE from existing page!" if params[:to_subpage]

  #     erb :"pages/new_for_tree", :layout => false, views: settings.views_admin
  #   else
  #     erb :"pages/new", views: settings.views_admin
  #   end

  # end 

  # copy for language version for standard and ajax 
  # get '/pages/:id/copy/:lang' do 

  #   extend Translate
  #   # protected!

  #   lang           = params[:lang]
  #   lang_folder    = settings.languages[lang][:folder]

  #   @source = Page.find(params[:id])
  #   @page   = @source.dup 


  #   unless  @source.parent.nil?   
  #       parent_page           = @source.parent
  #       parent_page_lang_url  = (lang_folder + parent_page.url).gsub(/\/\z/, "")
  #       parent_page_lang      = Page.where(url: parent_page_lang_url).first
  #       @page.parent_id       = parent_page_lang.id

  #   else # если нужно создать заглавную страницу по языку, у нее parent == nil
  #       parent_page           = Page.find(1)
  #       parent_page_lang_url  = (lang_folder + parent_page.url).gsub(/\/\z/, "")
  #       parent_page_lang      = Page.where(url: "/").first
  #       @page.parent_id       = nil
  #   end

  #   @page.url          = (lang_folder + @source.url).gsub(/\/\z/, "")
  #   @page.lang         = lang
  #   @page.base_id      = @source.id
  #   @page.lang_ref     = @source.lang_ref
  #   @page.ready        = true
  #   @page.published    = false

  #   @page.title = Translate.translate(@source.title, 'sl', lang)
  #   @page.h1 = Translate.translate(@source.h1, 'sl', lang)
  #   @page.sub = Translate.translate(@source.sub, 'sl', lang)
  #   @page.meta_description = Translate.translate(@source.meta_description, 'sl', lang)
  #   @page.anchor_1 = Translate.translate(@source.anchor_1, 'sl', lang)
  #   @page.anchor_2 = Translate.translate(@source.anchor_2, 'sl', lang)
  #   @page.anchor_3 = Translate.translate(@source.anchor_3, 'sl', lang)
    
  #   #@page.body         = parent_page_lang_url  # это для отладки использовал
    
  #   if params[:ajax]
  #     @info = "You are coping to #{params[:lang]} version of page"
    
  #     erb :"pages/new_for_tree", :layout => false, views: settings.views_admin
  #   else
  #     erb :"pages/new", views: settings.views_admin
  #   end

  # end 


  # create - ajax 
  # post '/pages/ajax' do 
  #   # protected!


  #   @page = Page.new(params[:page])

  #   if @page.save

  #     @page.lang_ref =  @page.id if @page.lang_ref == '' || @page.lang_ref == nil

  #     @page.save
      
  #       if params[:source_page_id] && !params[:source_page_id].blank?
  #         source_page = Page.find(params[:source_page_id].to_i)

  #         # 2. КОПИРУЕМ ТЕГИ (has_many :through)
  #         # Мы просто передаем массив существующих тегов. 
  #         # ActiveRecord сам создаст новые записи в соединительной таблице `taggings` при сохранении @page.
  #         @page.tags = source_page.tags

  #         # 3. КОПИРУЕМ DETAILS (has_many с nested attributes)
  #         # Так как детали — это отдельные записи в базе, их нужно тоже продублировать через .dup,
  #         # чтобы они создались с новыми id и привязались к новой странице.
  #         source_page.details.each do |detail|
  #           duplicated_detail = detail.dup
  #           # Меняем значение body на нужную строку
  #           duplicated_detail.body = 'edit me!'
  #           @page.details << duplicated_detail
  #         end

  #       end

  #       @page.save


  #        notice =  "<div class='content'>"
  #        notice += "  <div class='notification is-success'>"
  #        notice += "    <button class='delete'></button>"
  #        notice += "    Page Created - copied"
  #        notice += "  </div>"
  #        notice += "</div>"
  #        notice += "<br>"
  #   else
  #        notice =  "<div class='content'>"
  #        notice += "  <div class='notification is-danger'>"
  #        notice += "    <button class='delete'></button>"
  #        notice += "    <p >Cannot create a new page:</p>"
  #        notice += "    <ol>" 
  #        @page.errors.full_messages.each do |msg|
  #           notice += "<li>" + msg
  #        end 
  #        notice += "    </ol>" 
  #        notice += "  </div>"
  #        notice += "</div>"
  #        notice += "<br>"
  #   end

  #   notice

  # end  


  # end  


  # def pages_tree(pages, padding=0, parent=0)
  #   abc = ""

  #   if parent != 0
  #     abc += "<div id='children_of_#{parent}'>"
  #   else 
  #     abc += "<div>"
  #   end  

  #   pages.order("position ASC").each do |page|  #.order(:position) 
  #   # pages.order(:url).each do |page|  #.order(:position) 
  #   # pages.order(:url).each do |page|  #.order(:position) 
  #   # pages.order(:url).each do |page|  #.order(:position) 

  #     #has_children = page.is_parent == true ? true : false
  #     has_children = page.has_children? 
  #     #has_template = (!page.template_id.nil? && page.template_id > 1) ? true : false 
  #     # has_template = !page.template_id.nil? && page.template_id >= 1 

  #     abc += "<nav class='level is-mobile' style='padding: 0px 0px 0px #{padding}px; margin:0px; '>"
  #     abc += "<div class='level-left'>"
  #     abc +=   "<div class='level-item'>"

  #     if has_children
  #       abc +=   "<i id='#{page.id}' class='far fa-plus-square fa-sm has-text-#{page.ready ? 'success' : 'grey-light' }'></i>"
  #     else
  #       abc +=   "<i id='#{page.id}' class='far fa-calendar-plus fa-sm is-invisible'></i>"
  #     end  
                 
  #     abc +=   "</div>"

  #     # abc +=   "<div class='level-item' id='wait_#{page.id}' style='display:none;'>"
  #     # abc +=   "  <i class='fas fa-spinner fa-spin'></i>"
  #     # abc +=   "</div>"

  #     # abc +=   "<div class='level-item'>"
  #     # abc +=     page.position.to_s if !page.position.nil? 
  #     # abc +=   "</div>"     

  #     # abc +=   "<div class='level-item'>"
  #     # abc +=     page.id.to_s 
  #     # abc +=   "</div>"   

  #     # abc +=   "<div class='level-item'>"
  #     # # abc +=     "t" if has_template
  #     # abc +=   "</div>"



  #     abc +=   "<div class='level-item'>"

  #     if page.category != 'profile'
  #       abc +=   "<span class='tag is-rounded'>#{page.category.first} </span>&nbsp;"
  #     else
  #       abc +=   "<span class='tag is-rounded'></span>&nbsp;"
  #     end

  #     abc +=     "<a href='#' id='#{page.id}' class='url_edit_page '> 

  #       <span class=' 
  #           #{has_children == true ? "has-text-weight-bold" : ''} 
  #           #{page.published == true ? "url_page_published" : 'url_page_not_published'}' 

  #         >  #{page.url} </span> </a> " 

  #     if ['profile', 'article'].include?(page.category) && [nil, 0].include?(page.base_id)
  #        # abc +=  #{page.category} 
  #        abc +=     "&nbsp; <a href='#' id='#{page.id}' class='url_page_tags_and_links'> <span class='tag'>#{page.tags.any? ? page.tags.length : '_'}</span></a> " 
  #        abc +=     "&nbsp;<a href='#' id='#{page.id}' class='url_page_pictures'> <span class='tag'>#{page.pictures.any? ? page.pictures.length : '&nbsp;'}</span></a>&nbsp;  " 
  #     elsif ['index', 'list'].include?(page.category) && [nil, 0].include?(page.base_id)
  #        abc +=     "<a href='#' id='#{page.id}' class='url_page_tags_and_links'> &nbsp;<span class='tag'>T</span></a> " 
  #     end

  #      # abc += 'p'


  #     abc +=   "</div>"
      
  #     abc += "</div>"
      
  #     abc += "<div class='level-right'>"



  #     abc +=   "<div class='level-item'>"
  #     #abc +=     page.title 
  #     abc +=   "</div>"

  #     #abc +=   "<div class='level-item'>"
  #     #(4-page.id.to_s.length).times{abc += '&nbsp;'}.to_s
  #     #abc +=  page.id.to_s
  #     #abc +=   "</div>"

  #     #abc +=   "<div class='level-item'>"
  #     #abc +=     "<i class='  #{page.noindex   ? 'fas fa-circle fa-xs has-text-danger' : 'far fa-circle fa-xs'}' title='noindex'   ></i>" 
  #     #abc +=     "<i class='  #{page.nofollow  ? 'fas fa-circle fa-xs has-text-danger' : 'far fa-circle fa-xs'}' title='nofollow'  ></i>" 
  #     #abc +=     "<i class='  #{page.sponsored ? 'fas fa-circle fa-xs has-text-danger' : 'far fa-circle fa-xs'}' title='sponsored' ></i>" 
  #     #abc +=     "<i class='  #{page.ugc       ? 'fas fa-circle fa-xs has-text-danger' : 'far fa-circle fa-xs'}' title='ugs'       ></i>"
  #     #abc +=  "</div>"  

  #  #   abc +=  "<div class='level-item'>
  #  #             <div class='field has-addons'>
  #  #               <a href='/admin/pages/new?page_id=#{page.id}' class='button is-small' title='Create subpage'><i class='fas fa-level-down-alt'></i></a>
  #  #              </div>      
  #  #           </div>"

  #     #abc +=  "<div class='level-item'> #{page.created_at.strftime('%d-%m-%y')} </div>" 
  #     #abc +=  "<div class='level-item'> #{page.updated_at.strftime('%d-%m-%y')} </div>"
      
  #     abc += "</div>"   
  #     abc += "</nav>"  

  #     if has_children
  #       abc += "<div id='children_of_#{page.id}' style='display:none;'></div>"  #nested_menus_edit_as_table(page.children, "40") 
  #     end  



  #   end

  #   abc += "</div>" 
  #   #abc += "" 
  #   return abc

  # end

  private

  # Модели, для которых допустимо создавать detail-страницу через
  # /pages/new?pageable_type=...&pageable_id=... (see PAGEABLE concern).
  PAGEABLE_TYPES = %w[Entity Item Event].freeze

  # Предзаполняет новую master-страницу данными сущности, для которой она
  # создаётся: title/h1 — entity.name, slug — транслитерированное имя,
  # layout/view — "default", pageable_type/pageable_id — сама сущность.
  def assign_pageable_defaults(page, pageable_type, pageable_id)
    return unless PAGEABLE_TYPES.include?(pageable_type)

    pageable = pageable_type.constantize.find_by(id: pageable_id)
    return unless pageable

    page.title         = pageable.name
    page.h1            = pageable.name
    page.slug          = SlugGenerator.call(pageable.name)
    page.layout        = "default"
    page.view          = "default"
    page.pageable_type = pageable_type
    page.pageable_id   = pageable.id
  end

  # page[conditions] приходит из textarea сырым JSON-текстом, а
  # serialize :conditions, JSON на модели ждёт уже распарсенный Hash —
  # парсим здесь, до mass-assignment. Ошибку возвращаем отдельно, а не
  # через @page.errors.add сразу: errors.clear происходит в начале
  # valid?/save, так что добавленная до save ошибка иначе потеряется.
  def normalize_page_conditions(raw_params)
    attrs = (raw_params || {}).to_h

    normalize_page_edited_at(attrs)

    return [attrs, nil] unless attrs.key?("conditions")

    raw_conditions = attrs["conditions"]

    if raw_conditions.blank?
      attrs["conditions"] = nil
      [attrs, nil]
    else
      begin
        attrs["conditions"] = JSON.parse(raw_conditions)
        [attrs, nil]
      rescue JSON::ParserError => e
        attrs.delete("conditions")
        [attrs, "невалидный JSON: #{e.message}"]
      end
    end
  end

  # <input type="date"> присылает только YYYY-MM-DD — время для edited_at
  # неважно (это просто отметка "было серьёзное обновление" для .rss),
  # поэтому дописываем время сохранения, а не молча ставим 00:00.
  def normalize_page_edited_at(attrs)
    return unless attrs.key?("edited_at")

    value = attrs["edited_at"]

    if value.blank?
      attrs["edited_at"] = nil
    elsif value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      attrs["edited_at"] = "#{value} #{Time.now.strftime('%H:%M:%S')}"
    end
  end

  # Сортировка корневых страниц в дереве: сначала главная страница
  # сайта (master root), затем переводы — в порядке, в котором языки
  # перечислены в settings.languages (а не по алфавиту lang).
  def sort_root_pages(root_pages)
    lang_order = settings.languages.keys.map(&:to_s)

    root_pages.sort_by do |page|
      next -1 if page.master?

      lang_order.index(page.lang) || lang_order.length
    end
  end

  def load_page_form_data
    scope = Page.all
    scope = scope.where.not(id: @page.id) if @page&.persisted?

    @parent_pages = scope.order(:lang, :uri)

    @master_pages = scope
                      .where(master_id: nil)
                      .order(:lang, :uri)
  end


end