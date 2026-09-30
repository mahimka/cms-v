class ItemsController < App

  namespace '/admin' do

    # index
    get '/items' do

      @q = Item.ransack(params[:q])
      @items_found = @q.result(distinct: true) # for index.rb
      @items       = @q.result(distinct: true).page(params[:page]).per(100)

      erb :"/items/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/items/new' do

      @item = Item.new

      erb :"/items/new", layout: :"/layout/wide", views: settings.views_admin

    end

    # create - step 1: только name и schema, details/tags/links заполняются позже
    post '/items' do

      item_params = params[:item] || {}
      @item = Item.new(name: item_params[:name], schema_id: item_params[:schema_id])

      if @item.save
        flash[:notice] = "Item created! Now fill in the details."
        redirect "/admin/items/#{@item.id}/edit"
      else
        flash.now[:error_title] = "Cannot create a new item:"
        flash.now[:errors] = @item.errors.full_messages
        erb :"/items/new", layout: :"/layout/wide", views: settings.views_admin
      end

    end

    get '/items/:id/edit' do

      @item = Item.find(params[:id])

      erb :"/items/edit", layout: :"/layout/wide", views: settings.views_admin

    end

    # Всё редактируется на месте (in_place_* хелперы + AJAX), без формы и
    # без единой перезагрузки страницы — см. app/helpers/in_place_editing_helpers.rb
    # и общий /admin/:table_name/:object_id/ajax в admin_controller.rb. Тот
    # же паттерн, что у entities/edit_in_place — см. entities_controller.rb.
    get '/items/:id/edit_in_place' do

      @item = Item.find(params[:id])

      erb :"/items/edit_in_place", layout: :"/layout/wide", views: settings.views_admin

    end

    # Отдаёт свежий HTML одной секции (details/links/profiles) без layout —
    # item-edit-in-place.js подставляет это вместо своего <div> после
    # AJAX-сохранения строки, вместо перезагрузки всей страницы.
    get '/items/:id/fields/:section' do
      halt 404 unless %w[details links profiles].include?(params[:section])

      @item = Item.find(params[:id])
      erb :"/items/_#{params[:section]}_fields", views: settings.views_admin, layout: false
    end

    # Тег — чекбоксом без формы (см. items/_tags_fields.erb на
    # edit_in_place): один клик — сразу AJAX, без общего "Update Item".
    post '/items/:id/tags/:tag_id/toggle' do
      item = Item.find(params[:id])
      tag_id = params[:tag_id].to_i

      if params[:checked] == "true"
        item.tag_ids |= [tag_id]
      else
        item.tag_ids -= [tag_id]
      end

      status 200
      "ok"
    end

    # update - step 2: остальные поля + tags (details теперь свои формы, см. DetailsController)
    patch '/items/:id' do

      @item = Item.find(params[:id])

      attributes = (params[:item] || {}).to_h.symbolize_keys

      if @item.update(attributes)
        @item.tag_ids = Array(params[:tag_ids]).reject(&:blank?)
        flash[:notice] = "Item updated!"
        redirect "/admin/items/#{@item.id}/edit"
      else
        flash.now[:error_title] = "Cannot update the item:"
        flash.now[:errors] = @item.errors.full_messages
        erb :"/items/edit", layout: :"/layout/wide", views: settings.views_admin
      end

    end

    get '/items/:id' do

      @item = Item.find(params[:id])

      erb :"/items/show", layout: :"/layout/wide", views: settings.views_admin

    end
  end


end
