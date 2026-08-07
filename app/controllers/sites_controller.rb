class SitesController < App

  namespace '/admin' do

    get '/sites' do
      @sites = Site.order(:name).page(params[:page]).per(100)
      erb :"/sites/index", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/sites/new' do
      @site = Site.new
      erb :"/sites/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/sites/:id/edit' do
      @site = Site.find(params[:id])
      erb :"/sites/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/sites' do
      @site = Site.new(params[:site])
      if @site.save
        flash[:notice] = "Site created!"
        redirect params[:redirect_to] || "/admin/sites/#{@site.id}/edit"
      else
        flash.now[:error_title] = "Cannot create a new site:"
        flash.now[:errors] = @site.errors.full_messages
        erb :"/sites/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/sites/:id' do
      @site = Site.find(params[:id])
      if @site.update(params[:site])
        flash[:notice] = "Site updated!"
        redirect "/admin/sites/#{@site.id}/edit"
      else
        flash.now[:error_title] = "Cannot update the site:"
        flash.now[:errors] = @site.errors.full_messages
        erb :"/sites/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

  end

end
