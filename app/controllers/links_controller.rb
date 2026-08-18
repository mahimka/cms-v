class LinksController < App

  LINKABLE_TYPES = %w[Entity Item Event].freeze

  namespace '/admin' do

    get '/links' do

      @q = Link.ransack(params[:q])
      @links_found = @q.result(distinct: true).size
      @links       = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(100)

      erb :"/links/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/links/new' do
      @link = Link.new(linkable_type: params[:linkable_type], linkable_id: params[:linkable_id])
      erb :"/links/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/links/:id' do
      @link = Link.find(params[:id])
      erb :"/links/show", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/links/:id/edit' do
      @link = Link.find(params[:id])
      erb :"/links/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/links' do
      @link = Link.new(params[:link])
      if @link.save
        halt 200, "ok" if request.xhr?
        flash[:notice] = "Link created!"
        redirect redirect_target_or(back_to_linkable_or('/admin/links'))
      else
        halt 422, @link.errors.full_messages.join(", ") if request.xhr?
        flash.now[:error_title] = "Cannot create a new link:"
        flash.now[:errors] = @link.errors.full_messages
        erb :"/links/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/links/:id' do
      @link = Link.find(params[:id])
      if @link.update(params[:link])
        halt 200, "ok" if request.xhr?
        flash[:notice] = "Link updated!"
        redirect redirect_target_or("/admin/links/#{@link.id}/edit")
      else
        halt 422, @link.errors.full_messages.join(", ") if request.xhr?
        flash.now[:error_title] = "Cannot update the link:"
        flash.now[:errors] = @link.errors.full_messages
        erb :"/links/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    delete '/links/:id' do
      @link = Link.find(params[:id])
      linkable = @link.linkable
      if @link.destroy
        halt 200, "ok" if request.xhr?
        flash[:notice] = "Link destroyed!"
        redirect redirect_target_or(linkable ? "/admin/#{linkable.class.name.underscore.pluralize}/#{linkable.id}" : '/admin/links')
      else
        halt 422, @link.errors.full_messages.join(", ") if request.xhr?
        flash[:error_title] = "Cannot destroy the link:"
        flash[:errors] = @link.errors.full_messages
        redirect redirect_target_or('/admin/links')
      end
    end

  end

  private

  # После создания ссылки удобнее вернуться на карточку linkable
  # (Entity/Item), откуда её и добавляли, чем на общий список.
  def back_to_linkable_or(fallback)
    return fallback if @link.linkable.nil?

    "/admin/#{@link.linkable.class.name.underscore.pluralize}/#{@link.linkable.id}"
  end

  # Формы, встроенные прямо в edit-страницу Entity/Item (см.
  # entities/_links_fields.erb), передают явный redirect_to, чтобы после
  # save/delete админ оставался на этой странице, а не улетал на /admin/links
  # или на карточку линкуемой записи. Принимаем только локальные /admin/*
  # пути, чтобы значением из формы нельзя было увести на внешний домен.
  def redirect_target_or(fallback)
    target = params[:redirect_to]
    target && target.start_with?('/admin/') ? target : fallback
  end

end
