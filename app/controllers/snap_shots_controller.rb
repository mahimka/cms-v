class SnapShotsController < App

  namespace '/admin' do

    get '/snap_shots' do

      @q = SnapShot.ransack(params[:q])
      @snap_shots_found = @q.result(distinct: true).size # for index.rb
      @snap_shots       = @q.result(distinct: true).page(params[:page]).per(50)
      erb :"/snap_shots/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/snap_shots/:id' do

      @snap_shot = SnapShot.find(params[:id])

      erb :"/snap_shots/show", layout: :"/layout/wide", views: settings.views_admin

    end

  end

end
