class EntitiesController < App

  namespace '/admin' do

    # index
    get '/entities' do

      @q = Entity.ransack(params[:q])
      @filter_tag_names = Array(params[:tag_names]).reject(&:blank?)

      result = @q.result(distinct: true)
      result = result.merge(Entity.tagged_with(@filter_tag_names, match: :all)) if @filter_tag_names.present?

      @entities_found = result # for index.rb
      @entities       = result.page(params[:page]).per(100)

      erb :"/entities/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/entities/new' do

      @entity = Entity.new

      erb :"/entities/new", layout: :"/layout/wide", views: settings.views_admin

    end

    # create - step 1: только name и schema, details/tags/links заполняются позже
    post '/entities' do

      entity_params = params[:entity] || {}
      @entity = Entity.new(name: entity_params[:name], schema_id: entity_params[:schema_id])

      if @entity.save
        flash[:notice] = "Entity created! Now fill in the details."
        redirect "/admin/entities/#{@entity.id}/edit"
      else
        flash.now[:error_title] = "Cannot create a new entity:"
        flash.now[:errors] = @entity.errors.full_messages
        erb :"/entities/new", layout: :"/layout/wide", views: settings.views_admin
      end

    end

    get '/entities/:id/edit' do

      @entity = Entity.find(params[:id])

      erb :"/entities/edit", layout: :"/layout/wide", views: settings.views_admin

    end

    # Всё редактируется на месте (in_place_* хелперы + AJAX), без формы и
    # без единой перезагрузки страницы — см. app/helpers/in_place_editing_helpers.rb
    # и общий /admin/:table_name/:object_id/ajax в admin_controller.rb.
    get '/entities/:id/edit_in_place' do

      @entity = Entity.find(params[:id])

      erb :"/entities/edit_in_place", layout: :"/layout/wide", views: settings.views_admin

    end

    # Отдаёт свежий HTML одной секции (details/links/profiles) без layout —
    # entity-edit-in-place.js подставляет это вместо своего <div> после
    # AJAX-сохранения строки, вместо перезагрузки всей страницы.
    get '/entities/:id/fields/:section' do
      halt 404 unless %w[details links profiles].include?(params[:section])

      @entity = Entity.find(params[:id])
      erb :"/entities/_#{params[:section]}_fields", views: settings.views_admin, layout: false
    end

    # Тег — чекбоксом без формы (см. entities/_tags_fields.erb на
    # edit_in_place): один клик — сразу AJAX, без общего "Update Entity".
    post '/entities/:id/tags/:tag_id/toggle' do
      entity = Entity.find(params[:id])
      tag_id = params[:tag_id].to_i

      if params[:checked] == "true"
        entity.tag_ids |= [tag_id]
      else
        entity.tag_ids -= [tag_id]
      end

      status 200
      "ok"
    end

    # update - step 2: остальные поля + tags (details теперь свои формы, см. DetailsController)
    patch '/entities/:id' do

      @entity = Entity.find(params[:id])

      attributes = (params[:entity] || {}).to_h.symbolize_keys

      if @entity.update(attributes)
        @entity.tag_ids = Array(params[:tag_ids]).reject(&:blank?)
        flash[:notice] = "Entity updated!"
        redirect "/admin/entities/#{@entity.id}/edit"
      else
        flash.now[:error_title] = "Cannot update the entity:"
        flash.now[:errors] = @entity.errors.full_messages
        erb :"/entities/edit", layout: :"/layout/wide", views: settings.views_admin
      end

    end

    get '/entities/:id' do

      @entity = Entity.find(params[:id])

      erb :"/entities/show", layout: :"/layout/wide", views: settings.views_admin

    end
  end

end
