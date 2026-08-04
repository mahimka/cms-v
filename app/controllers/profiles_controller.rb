class ProfilesController < App

  namespace '/admin' do 

    # index 
    get '/profiles' do 

      @q = Profile.ransack(params[:q])
      @profiles_found = @q.result(distinct: true) # for index.rb
      @profiles       = @q.result(distinct: true).page(params[:page]).per(100)

      erb :"/profiles/index", layout: :"/layout/wide", views: settings.views_admin

    end  
  end


end



