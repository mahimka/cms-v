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

    # Всё редактируется на месте (in_place_* хелперы + AJAX), без формы и
    # без единой перезагрузки страницы — см. app/helpers/in_place_editing_helpers.rb
    # и общий /admin/:table_name/:object_id/ajax в admin_controller.rb. Тот
    # же паттерн, что у entities/edit_in_place — см. entities_controller.rb.
    get '/events/:id/edit_in_place' do

      @event = Event.find(params[:id])

      erb :"/events/edit_in_place", layout: :"/layout/wide", views: settings.views_admin

    end

    # Отдаёт свежий HTML одной секции (details/links/profiles) без layout —
    # event-edit-in-place.js подставляет это вместо своего <div> после
    # AJAX-сохранения строки, вместо перезагрузки всей страницы.
    get '/events/:id/fields/:section' do
      halt 404 unless %w[details links profiles].include?(params[:section])

      @event = Event.find(params[:id])
      erb :"/events/_#{params[:section]}_fields", views: settings.views_admin, layout: false
    end

    # Тег — чекбоксом без формы (см. events/_tags_fields.erb на
    # edit_in_place): один клик — сразу AJAX, без общего "Update Event".
    post '/events/:id/tags/:tag_id/toggle' do
      event = Event.find(params[:id])
      tag_id = params[:tag_id].to_i

      if params[:checked] == "true"
        event.tag_ids |= [tag_id]
      else
        event.tag_ids -= [tag_id]
      end

      status 200
      "ok"
    end

    # update - step 2: остальные поля + tags (details теперь свои формы, см. DetailsController)
    patch '/events/:id' do

      @event = Event.find(params[:id])

      attributes = (params[:event] || {}).to_h.symbolize_keys

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


end
