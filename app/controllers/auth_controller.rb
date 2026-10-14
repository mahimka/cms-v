# Вход посетителей (User + identities в main.db): письмо со ссылкой и Google.
# Старые /login и /register (пароль) работают как раньше; сессия общая: session[:user_id].
# Ключи: config/secret.yml -> google_oauth: {client_id, client_secret}, smtp: {...}.
# Без google_oauth кнопка Google не показывается; без smtp ссылка пишется в log/mail.log.
class AuthController < App

  GOOGLE = (settings.respond_to?(:google_oauth) ? settings.google_oauth : nil) || {}
  GOOGLE_ENABLED = !GOOGLE['client_id'].to_s.empty?

  OmniAuth.config.allowed_request_methods = [:post]   # OmniAuth 2: только POST + CSRF-токен
  OmniAuth.config.logger = Logger.new($stderr, level: Logger::WARN)
  OmniAuth.config.on_failure = proc { |env| [302, { 'Location' => '/auth/failure' }, []] }

  if GOOGLE_ENABLED
    use OmniAuth::Builder do
      provider :google_oauth2, GOOGLE['client_id'], GOOGLE['client_secret'],
               scope: 'email,profile', prompt: 'select_account', path_prefix: '/auth'
    end
  end

  get '/signin' do
    session[:return_to] = local_path(params[:redirect_to]) if params[:redirect_to]
    redirect(return_path) if current_user
    render_standalone('signin.erb')
  end

  post '/auth/email' do
    halt 403, 'CSRF' unless csrf_ok?
    email = params[:email].to_s.strip.downcase

    if email =~ URI::MailTo::EMAIL_REGEXP && LoginToken.allowed?(email: email, ip: request.ip)
      raw = LoginToken.issue(email: email, ip: request.ip)
      Mailer.deliver(
        to: email,
        subject: "Вход на #{settings.site_name}",
        body: "Для входа перейдите по ссылке (действует 15 минут):\n\n" \
              "https://#{settings.domain}/auth/email/confirm?token=#{raw}\n\n" \
              "Если вы не запрашивали вход, просто проигнорируйте письмо."
      )
    end
    # Всегда один и тот же ответ: не выдаём, есть ли такой адрес и сработал ли лимит.
    flash[:notice] = "Если адрес верный, мы отправили на него ссылку для входа."
    redirect '/signin'
  end

  # GET только показывает кнопку: почтовые сканеры открывают ссылки сами и сожгли бы токен.
  get '/auth/email/confirm' do
    @token = params[:token].to_s
    render_standalone('signin_confirm.erb')
  end

  post '/auth/email/confirm' do
    halt 403, 'CSRF' unless csrf_ok?
    email = LoginToken.consume(params[:token])
    unless email
      flash[:error_title] = "Ссылка недействительна или устарела. Запросите новую."
      redirect '/signin'
    end
    user = User.sign_in_with(provider: 'email', uid: email, email: email, email_verified: true)
    sign_in!(user)
  end

  get '/auth/google/callback' do
    a    = request.env['omniauth.auth'] or redirect('/auth/failure')
    info = a['info'] || {}
    user = User.sign_in_with(
      provider: 'google', uid: a['uid'], email: info['email'],
      email_verified: a.dig('extra', 'raw_info', 'email_verified') == true,
      name: info['name'], avatar_url: info['image']
    )
    sign_in!(user)
  end

  get '/auth/failure' do
    flash[:error_title] = "Не удалось войти. Попробуйте ещё раз."
    redirect '/signin'
  end

  get '/signout' do
    session.delete(:user_id)
    redirect '/'
  end

  helpers do
    def sign_in!(user)
      if user.nil? || user.blocked?
        flash[:error_title] = "Не удалось войти: аккаунт недоступен или email не подтверждён."
        redirect '/signin'
      end
      back = return_path
      session.clear                       # новая сессия после входа (защита от фиксации)
      session[:user_id] = user.id
      redirect back
    end

    def return_path = local_path(session[:return_to]) || '/'

    # Только локальные пути (защита от open redirect).
    def local_path(path)
      path = path.to_s
      path.start_with?('/') && !path.start_with?('//') ? path : nil
    end

    def csrf_ok?
      Rack::Protection::AuthenticityToken.new(->(_) {}).accepts?(env)
    end

    def csrf_token = Rack::Protection::AuthenticityToken.token(session)

    def render_standalone(name)
      path = [File.join(settings.views_project, name), File.join(settings.views, name)]
             .find { |f| File.file?(f) }
      halt 500, "Шаблон '#{name}' не найден" unless path
      erb path.sub(/\.erb\z/, '').to_sym, layout: false, views: '/'
    end
  end
end
