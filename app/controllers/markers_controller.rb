class MarkersController < App

  namespace '/admin' do

    get '/markers' do

      @q = Marker.ransack(params[:q])
      @markers_found = @q.result(distinct: true).size # for index.rb
      @markers       = @q.result(distinct: true).page(params[:page]).per(50)
      erb :"/markers/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/markers/:id' do

      @marker = Marker.find(params[:id])

      erb :"/markers/show", layout: :"/layout/wide", views: settings.views_admin

    end

  end

end
