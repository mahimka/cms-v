class DetailsController < App

  DETAILABLE_TYPES = %w[Entity Item Event].freeze

  namespace '/admin' do

    get '/details' do

      @q = Detail.ransack(params[:q])
      @details_found = @q.result(distinct: true).size
      @details       = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(100)

      erb :"/details/index", layout: :"/layout/wide", views: settings.views_admin

    end

    post '/details' do
      @detail = Detail.new(params[:detail])
      if @detail.save
        flash[:notice] = "Deталь создана!"
        redirect redirect_target_or(back_to_detailable_or('/admin/details'))
      else
        flash[:error_title] = "Не удалось создать деталь:"
        flash[:errors] = @detail.errors.full_messages
        redirect redirect_target_or(back_to_detailable_or('/admin/details'))
      end
    end

    patch '/details/:id' do
      @detail = Detail.find(params[:id])
      if @detail.update(params[:detail])
        flash[:notice] = "Деталь обновлена!"
        redirect redirect_target_or(back_to_detailable_or('/admin/details'))
      else
        flash[:error_title] = "Не удалось обновить деталь:"
        flash[:errors] = @detail.errors.full_messages
        redirect redirect_target_or(back_to_detailable_or('/admin/details'))
      end
    end

    delete '/details/:id' do
      @detail = Detail.find(params[:id])
      detailable = @detail.detailable
      if @detail.destroy
        flash[:notice] = "Деталь удалена!"
        redirect redirect_target_or(detailable ? "/admin/#{detailable.class.name.underscore.pluralize}/#{detailable.id}" : '/admin/details')
      else
        flash[:error_title] = "Не удалось удалить деталь:"
        flash[:errors] = @detail.errors.full_messages
        redirect redirect_target_or('/admin/details')
      end
    end

  end

  private

  # После создания/обновления детали удобнее вернуться на карточку
  # detailable (Entity/Item/Event), откуда её и добавляли, чем на общий
  # список — см. тот же приём в LinksController#back_to_linkable_or.
  def back_to_detailable_or(fallback)
    return fallback if @detail.detailable.nil?

    "/admin/#{@detail.detailable.class.name.underscore.pluralize}/#{@detail.detailable.id}"
  end

  # Формы, встроенные прямо в edit-страницу Entity/Item/Event (см.
  # entities/_details_fields.erb), передают явный redirect_to, чтобы
  # после save/delete админ оставался на этой странице. Принимаем
  # только локальные /admin/* пути.
  def redirect_target_or(fallback)
    target = params[:redirect_to]
    target && target.start_with?('/admin/') ? target : fallback
  end

end
