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
