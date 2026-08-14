class HistoriesController < App

  namespace '/admin' do

    # index
    get '/histories' do

      @q = History.ransack(params[:q])
      @histories_found = @q.result(distinct: true) # for index.rb
      @histories       = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(100)

      erb :"/histories/index", layout: :"/layout/wide", views: settings.views_admin

    end

    # new — ручное добавление редиректа (обычно записи создаются
    # автоматически из Page при смене uri, см. History#page comment)
    get '/histories/new' do
      @history = History.new(redirect_code: 301)
      erb :"/histories/new", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/histories' do
      @history = History.new(params[:history])
      if @history.save
        flash[:notice] = "History created!"
        redirect '/admin/histories'
      else
        flash.now[:error_title] = "Cannot create a new history:"
        flash.now[:errors] = @history.errors.full_messages
        erb :"/histories/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end
  end

end
