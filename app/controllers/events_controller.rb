class EventsController < App

  namespace '/admin' do

    # index
    get '/events' do

      @q = Event.ransack(params[:q])
      @events_found = @q.result(distinct: true)
      @events       = @q.result(distinct: true).order(start_at: :desc).page(params[:page]).per(100)

      erb :"/events/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/events/new' do

      @event = Event.new

      erb :"/events/new", layout: :"/layout/wide", views: settings.views_admin

    end

    # create - step 1: только name и schema, остальное заполняется позже
    post '/events' do

      event_params = params[:event] || {}
      @event = Event.new(name: event_params[:name], schema_id: event_params[:schema_id])

      if @event.save
        flash[:notice] = "Event created! Now fill in the details."
        redirect "/admin/events/#{@event.id}/edit"
      else
        flash.now[:error_title] = "Cannot create a new event:"
        flash.now[:errors] = @event.errors.full_messages
        erb :"/events/new", layout: :"/layout/wide", views: settings.views_admin
      end

    end

    get '/events/:id/edit' do

      @event = Event.find(params[:id])

      erb :"/events/edit", layout: :"/layout/wide", views: settings.views_admin

    end

    # update - step 2: остальные поля + details (hash параметр: значение) + tags
    patch '/events/:id' do

      @event = Event.find(params[:id])

      attributes = (params[:event] || {}).to_h.symbolize_keys
      attributes[:details] = details_hash_from_params

      if @event.update(attributes)
        @event.tag_ids = Array(params[:tag_ids]).reject(&:blank?)
        flash[:notice] = "Event updated!"
        redirect "/admin/events/#{@event.id}/edit"
      else
        flash.now[:error_title] = "Cannot update the event:"
        flash.now[:errors] = @event.errors.full_messages
        erb :"/events/edit", layout: :"/layout/wide", views: settings.views_admin
      end

    end

    get '/events/:id' do

      @event = Event.find(params[:id])

      erb :"/events/show", layout: :"/layout/wide", views: settings.views_admin

    end
  end

  private

  # Собирает hash деталей из параллельных массивов полей формы
  # (details_keys[] / details_values[]) в { "key" => "value" }.
  # Пустые ключи отбрасываются.
  def details_hash_from_params
    keys   = Array(params[:details_keys])
    values = Array(params[:details_values])

    keys.zip(values).each_with_object({}) do |(key, value), hash|
      next if key.blank?

      hash[key] = value
    end
  end

end
