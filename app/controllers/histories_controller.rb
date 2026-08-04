class HistoriesController < App

  namespace '/admin' do

    # index
    get '/histories' do

      @q = History.ransack(params[:q])
      @histories_found = @q.result(distinct: true) # for index.rb
      @histories       = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(100)

      erb :"/histories/index", layout: :"/layout/wide", views: settings.views_admin

    end
  end

end
