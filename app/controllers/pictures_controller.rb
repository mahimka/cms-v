class PicturesController < App

  IMAGEABLE_TYPES = %w[Entity Item Event].freeze

  namespace '/admin' do

    get '/pictures' do

      @q = Picture.ransack(params[:q])
      @pictures_found = @q.result(distinct: true).size
      @pictures       = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(100)

      erb :"/pictures/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/pictures/new' do
      @picture = Picture.new(imageable_type: params[:imageable_type], imageable_id: params[:imageable_id])
      erb :"/pictures/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/pictures/:id' do
      @picture = Picture.find(params[:id])
      erb :"/pictures/show", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/pictures/:id/edit' do
      @picture = Picture.find(params[:id])
      erb :"/pictures/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/pictures' do
      @picture = Picture.new(params[:picture])
      if @picture.save
        @picture.tag_ids = Array(params[:tag_ids]).reject(&:blank?)
        flash[:notice] = "Picture created!"
        redirect redirect_target_or(back_to_imageable_or('/admin/pictures'))
      else
        flash.now[:error_title] = "Cannot create a new picture:"
        flash.now[:errors] = @picture.errors.full_messages
        erb :"/pictures/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/pictures/:id' do
      @picture = Picture.find(params[:id])
      if @picture.update(params[:picture])
        @picture.tag_ids = Array(params[:tag_ids]).reject(&:blank?)
        flash[:notice] = "Picture updated!"
        redirect redirect_target_or("/admin/pictures/#{@picture.id}/edit")
      else
        flash.now[:error_title] = "Cannot update the picture:"
        flash.now[:errors] = @picture.errors.full_messages
        erb :"/pictures/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    delete '/pictures/:id' do
      @picture = Picture.find(params[:id])
      imageable = @picture.imageable
      if @picture.destroy
        flash[:notice] = "Picture destroyed!"
        redirect redirect_target_or(imageable ? "/admin/#{imageable.class.name.underscore.pluralize}/#{imageable.id}" : '/admin/pictures')
      else
        flash[:error_title] = "Cannot destroy the picture:"
        flash[:errors] = @picture.errors.full_messages
        redirect redirect_target_or('/admin/pictures')
      end
    end

  end

  private

  # После создания картинки удобнее вернуться на карточку imageable
  # (Entity/Item), откуда её и добавляли, чем на общий список.
  def back_to_imageable_or(fallback)
    return fallback if @picture.imageable.nil?

    "/admin/#{@picture.imageable.class.name.underscore.pluralize}/#{@picture.imageable.id}"
  end

  # Формы, встроенные прямо в edit-страницу Entity/Item, передают явный
  # redirect_to, чтобы после save/delete админ оставался на этой странице.
  # Принимаем только локальные /admin/* пути (защита от open redirect).
  def redirect_target_or(fallback)
    target = params[:redirect_to]
    target && target.start_with?('/admin/') ? target : fallback
  end

end
