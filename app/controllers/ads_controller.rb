class AdsController < App

  namespace '/admin' do

    get '/ads' do
      @q = Ad.ransack(params[:q])
      @ads_found = @q.result(distinct: true).size
      @ads       = @q.result(distinct: true).order(:ancestry, :name).page(params[:page]).per(500)

      erb :"/ads/index", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/ads/new' do
      if params[:parent_id]
        @ad = Ad.new(parent_id: params[:parent_id])
      else
        @ad = Ad.new
      end
      erb :"/ads/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/ads/:id' do
      @ad = Ad.find(params[:id])
      erb :"/ads/show", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/ads/:id/edit' do
      @ad = Ad.find(params[:id])
      erb :"/ads/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/ads' do
      @ad = Ad.new(params[:ad])
      if @ad.save
        flash[:notice] = "Ad created!"
        redirect '/admin/ads'
      else
        flash.now[:error_title] = "Cannot create a new ad:"
        flash.now[:errors] = @ad.errors.full_messages
        erb :"/ads/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/ads/:id' do
      @ad = Ad.find(params[:id])
      if @ad.update(params[:ad].except(:id))
        flash[:notice] = "Ad updated!"
        redirect "/admin/ads/#{@ad.id}/edit"
      else
        flash.now[:error_title] = "Cannot update the ad:"
        flash.now[:errors] = @ad.errors.full_messages
        erb :"/ads/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    delete '/ads/:id' do
      @ad = Ad.find(params[:id])
      if @ad.destroy
        flash[:notice] = "Ad destroyed!"
        redirect '/admin/ads'
      else
        flash[:error_title] = "Cannot destroy the ad:"
        flash[:errors] = @ad.errors.full_messages
        redirect '/admin/ads'
      end
    end

  end

end
