class LinksController < App

  LINKABLE_TYPES = %w[Entity Item Event].freeze

  namespace '/admin' do

    get '/links' do

      @q = Link.ransack(params[:q])
      @links_found = @q.result(distinct: true).size
      @links       = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(100)

      # Отчёт для секции статусов — по всей таблице, не по текущему
      # фильтру ransack (иначе цифры "сколько всего не проверено" скачут
      # вместе с фильтром и вводят в заблуждение).
      @checked_stats = {
        total:      Link.count,
        checked:    Link.where.not(checked_at: nil).count,
        unchecked:  Link.where(checked_at: nil).count,
        alive:      Link.where(alive: true).count,
        dead:       Link.where(alive: false).count,
        redirected: Link.where(redirected: true).count,
        stale:      Link.where("checked_at IS NULL OR checked_at < ?", 15.days.ago).count,
      }
      @checked_by_label = Link.joins(:label)
                               .group("labels.name")
                               .select("labels.name AS label_name, COUNT(*) AS total, SUM(CASE WHEN links.checked_at IS NOT NULL THEN 1 ELSE 0 END) AS checked, SUM(CASE WHEN links.alive = 0 THEN 1 ELSE 0 END) AS dead")

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

    # Ручная проверка одной ссылки — см. lib/link_checker.rb. Всегда
    # проверяет конкретно эту ссылку, даже если она сейчас alive:false —
    # это явный клик по конкретной записи, а не плановая выборка
    # (в отличие от tasks/links.rake, который мёртвые по умолчанию пропускает).
    post '/links/:id/check' do
      @link = Link.find(params[:id])
      @link.check!
      halt 200, "ok" if request.xhr?
      redirect redirect_target_or("/admin/links/#{@link.id}")
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
