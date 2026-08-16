class UsersController < App

  namespace '/admin' do

    get '/users' do
      @q = User.ransack(params[:q])
      @users_found = @q.result(distinct: true).size
      @users       = @q.result(distinct: true).order(:name).page(params[:page]).per(100)

      erb :"/users/index", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/users/new' do
      @user = User.new
      erb :"/users/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/users/:id/edit' do
      @user = User.find(params[:id])
      erb :"/users/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/users' do
      @user = User.new(params[:user])
      if @user.save
        flash[:notice] = "User created!"
        redirect '/admin/users'
      else
        flash.now[:error_title] = "Cannot create a new user:"
        flash.now[:errors] = @user.errors.full_messages
        erb :"/users/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/users/:id' do
      @user = User.find(params[:id])

      # Пустой пароль при редактировании — значит "не менять" (has_secure_password
      # иначе потребовал бы его на каждое сохранение).
      attrs = params[:user].to_h
      attrs.delete(:password) if attrs[:password].blank?

      if @user.update(attrs)
        flash[:notice] = "User updated!"
        redirect "/admin/users/#{@user.id}/edit"
      else
        flash.now[:error_title] = "Cannot update the user:"
        flash.now[:errors] = @user.errors.full_messages
        erb :"/users/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    delete '/users/:id' do
      @user = User.find(params[:id])
      if @user.destroy
        flash[:notice] = "User destroyed!"
        redirect '/admin/users'
      else
        flash[:error_title] = "Cannot destroy the user:"
        flash[:errors] = @user.errors.full_messages
        redirect '/admin/users'
      end
    end

  end

end
