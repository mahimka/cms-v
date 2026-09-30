class PageTemplatesController < App

  namespace '/admin' do

    get '/page_templates' do
      @q = PageTemplate.ransack(params[:q])
      @page_templates_found = @q.result(distinct: true).size

      base_order = @q.result(distinct: true).order(:template_type, :lang, :slug).to_a
      ordered, @page_template_depths = PageTemplate.tree_order(base_order)
      @page_templates = Kaminari.paginate_array(ordered).page(params[:page]).per(100)

      erb :"/page_templates/index", layout: :"/layout/wide", views: settings.views_admin
    end

    # ?copy_from=N — кнопка "copy" в index: форма создания нового
    # template, предзаполненная ВСЕМИ полями исходного (кроме id/
    # timestamps) — ничего не сохраняется, пока админ сам не нажмёт
    # Create, можно поправить что угодно перед сохранением.
    #
    # ?parent_template_id=N — форма "добавить вложенный template" (кнопка
    # у List-строк в index) — предзаполняем то, что для вложенного
    # template'а обязательно (template_type/pageable_type/lang как у
    # родителя), чтобы админ не мог ошибиться руками. parent_page_id для
    # вложенного template'а игнорируется генератором (см.
    # PageTemplateGenerator) — в форме его в этом случае вообще не
    # показываем, см. _form.erb.
    get '/page_templates/new' do
      source = PageTemplate.find_by(id: params[:copy_from])
      parent_template = PageTemplate.find_by(id: params[:parent_template_id], template_type: "List")

      @page_template =
        if source
          PageTemplate.new(source.attributes.except("id", "created_at", "updated_at"))
        elsif parent_template
          PageTemplate.new(
            parent_template_id: parent_template.id,
            template_type: "List",
            pageable_type: parent_template.pageable_type,
            lang: parent_template.lang
          )
        else
          PageTemplate.new(lang: settings.home_language)
        end

      erb :"/page_templates/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/page_templates/:id/edit' do
      @page_template = PageTemplate.find(params[:id])
      erb :"/page_templates/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/page_templates' do
      @page_template = PageTemplate.new(params[:page_template])
      if @page_template.save
        flash[:notice] = "Page template created!"
        redirect "/admin/page_templates/#{@page_template.id}/edit"
      else
        flash.now[:error_title] = "Cannot create a new page template:"
        flash.now[:errors] = @page_template.errors.full_messages
        erb :"/page_templates/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/page_templates/:id' do
      @page_template = PageTemplate.find(params[:id])
      if @page_template.update(params[:page_template])
        flash[:notice] = "Page template updated!"
        redirect "/admin/page_templates/#{@page_template.id}/edit"
      else
        flash.now[:error_title] = "Cannot update the page template:"
        flash.now[:errors] = @page_template.errors.full_messages
        erb :"/page_templates/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    # Генерация страниц по template_type "Profile" или "List" (см.
    # PageTemplateGenerator). force=true — обновляет и уже существующие
    # страницы, по умолчанию только создаёт недостающие.
    #
    # redirect_to — куда вернуться после генерации: кнопки в index (там же,
    # с сохранением фильтра/страницы — не нужно каждый раз заходить в
    # edit ради одной генерации) передают текущий /admin/page_templates?...,
    # кнопки в edit.erb ничего не передают — редирект туда же, как раньше.
    post '/page_templates/:id/generate' do
      page_template = PageTemplate.find(params[:id])
      force = params[:force] == "true"
      result = PageTemplateGenerator.run(page_template, force: force)
      flash[:notice] = "Template ##{page_template.id}: создано #{result[:created].size}, обновлено #{result[:updated].size}, пропущено (уже есть) #{result[:skipped].size}"

      # только относительный /admin/... — не open redirect на чужой хост
      safe_redirect = params[:redirect_to].to_s.start_with?("/admin/") ? params[:redirect_to] : nil
      redirect safe_redirect || "/admin/page_templates/#{page_template.id}/edit"
    end

    delete '/page_templates/:id' do
      @page_template = PageTemplate.find(params[:id])
      if @page_template.destroy
        flash[:notice] = "Page template destroyed!"
        redirect '/admin/page_templates'
      else
        flash[:error_title] = "Cannot destroy the page template:"
        flash[:errors] = @page_template.errors.full_messages
        redirect '/admin/page_templates'
      end
    end

  end

end
