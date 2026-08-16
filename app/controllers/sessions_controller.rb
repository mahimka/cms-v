class SessionsController < App

  get '/login' do
    erb :login, layout: false, views: settings.views_project
  end

  post '/login' do
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password].to_s)
      session[:user_id] = user.id
      redirect safe_redirect_target
    else
      flash[:error_title] = "Неверный email или пароль"
      redirect "/login?redirect_to=#{Rack::Utils.escape(safe_redirect_target)}"
    end
  end

  get '/logout' do
    session.clear
    redirect safe_redirect_target
  end

  private

  # Принимаем только локальные пути (защита от open redirect) — тот же
  # приём, что и redirect_target_or в PicturesController, только без
  # ограничения на /admin/*, раз это публичные роуты.
  def safe_redirect_target
    target = params[:redirect_to]
    target && target.start_with?('/') && !target.start_with?('//') ? target : '/'
  end

end
