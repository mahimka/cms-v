# Логин/регистрация — общая CMS-фича (не project-specific): вьюхи лежат
# в app/views/login.erb и app/views/register.erb — самодостаточные
# страницы (свой <html>/<head>, без сайтового layout), поэтому не через
# call_erb_view (тот ВСЕГДА подставляет какой-нибудь layout — свой,
# либо app/views/layout/default.erb — задвоило бы <html>). Тот же
# двухуровневый поиск (project/views -> app/views), что и у
# call_erb_view, просто без слоя layout — см. #standalone_view_path.
# Так любой проект на этом коде получает рабочие /login и /register из
# коробки без своего project/views/login.erb — а если он всё же нужен
# (свой дизайн под конкретный проект), достаточно положить файл с тем же
# именем в project/views, он переопределит общий.
class SessionsController < App

  get '/login' do
    render_standalone('login.erb')
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

  get '/register' do
    @user = User.new(email: params[:email])
    render_standalone('register.erb')
  end

  post '/register' do
    # Тот же путь использует android-приложение (AJPES, см. RoutesFirst):
    # запросы с API-ключом или JSON отдаём туда, а не в форму регистрации.
    pass if request.env['HTTP_X_API_KEY'] ||
            request.env['HTTP_AUTHORIZATION'].to_s.start_with?('Bearer ') ||
            request.media_type == 'application/json'

    @user = User.new(
      name: params[:name].to_s.strip,
      email: params[:email].to_s.strip.downcase,
      password: params[:password].to_s
    )

    if @user.save
      session[:user_id] = @user.id
      redirect safe_redirect_target
    else
      flash.now[:error_title] = "Не удалось зарегистрироваться"
      flash.now[:errors] = @user.errors.full_messages
      render_standalone('register.erb')
    end
  end

  private

  # Принимаем только локальные пути (защита от open redirect) — тот же
  # приём, что и redirect_target_or в PicturesController, только без
  # ограничения на /admin/*, раз это публичные роуты.
  def safe_redirect_target
    target = params[:redirect_to]
    target && target.start_with?('/') && !target.start_with?('//') ? target : '/'
  end

  # project/views -> app/views, без layout (страница сама себе <html>) —
  # тот же порядок поиска, что у call_erb_view, но тот не умеет "совсем
  # без layout" (всегда подставляет хотя бы app/views/layout/default.erb).
  def render_standalone(name)
    path = [
      File.join(settings.views_project, name),
      File.join(settings.views, name)
    ].find { |f| File.file?(f) }

    halt 500, "Шаблон '#{name}' не найден ни в project/views, ни в app/views" unless path

    erb path.sub(/\.erb\z/, '').to_sym, layout: false, views: '/'
  end

end
