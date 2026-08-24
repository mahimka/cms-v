## двинуть в инвайронтмент??
require "sinatra/base" 
require 'sinatra/reloader'       
require "sinatra/config_file"
require "sinatra/content_for" 
require "sinatra/namespace"    

Ancestry.default_ancestry_format = :materialized_path2



# Подключение для статистики
class GscRecord < ActiveRecord::Base
  self.abstract_class = true
  # establish_connection({ adapter: 'sqlite3', database: 'db/stats.sqlite3' })
  establish_connection({ adapter: 'sqlite3', database: 'db/gsc.db' })
end



class App < Sinatra::Base    

  use Rack::MethodOverride

  # подключаю списки для стран и прочего, там - константы - маасивы стран
  # include AdsLists # константы для формироварния списков из /lib/Lists.rb
  
  register Sinatra::Namespace
  register Sinatra::ConfigFile

  config_file [
    "./config/config.yml", 
    "./config/secret.yml",
    "./config/languages.yml" 
    # "./config/config_folders.yml", 
    # "./config/baza_objects.yml"
  ]
  
  configure do
    set :public_folder, File.dirname(__FILE__) + '/public'
    set :views_admin,   File.dirname(__FILE__) + '/app/views/admin'
    set :views_project, File.dirname(__FILE__) + '/project/views'
    set :views, File.dirname(__FILE__) + '/app/views'

    # set :show_exceptions, true #заставляет Sinatra сразу пере-raise'ить ошибку
    # enable :logging
  end

  # для своей debug-страницы с полным бэктрейсом и дампом ENV/COOKIES —
  # это только для разработки (см. configure :development ниже).
  # В остальных окружениях show_exceptions остаётся false (дефолт), чтобы
  # сработал error 500 do...end и посетитель не увидел внутренности сервера.
  error 500 do
    if (err = env['sinatra.error'])
      File.open(File.join(settings.root, 'log', 'app_errors.log'), 'a') do |f|
        f.flock(File::LOCK_EX)
        f.puts "[#{Time.now.utc}] #{request.request_method} #{request.path} :: #{err.class}: #{err.message}"
        f.puts err.backtrace.first(15).join("\n")
        f.puts '---'
      end
    end
    erb :"errors/500", layout: false
  end

  # def show_timing(block_name)
  #   if @auth && @auth.provided? && settings.show_timings == true 
  #     timing = (Time.now - @start_time_render).round(3)*1000
  #     abc = "<span class='tag #{timing > 5.00 ? 'is-danger' : 'is-warning'}'>#{block_name} #{timing}</span>" 
  #   end
  #   @start_time_render = Time.now
  #   return abc
  # end

  # === start of auth from # http://sinatrarb.com/faq.html#auth ===

  helpers do  
    def protected! 
      return if authorized?     
      headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      halt 401, "Not authorized\n"
    end  
    
    def authorized?
      @auth ||=  Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == [settings.cms['login'].to_s, settings.cms['password'].to_s]
    end

    # Залогиненный посетитель сайта (не путать с админом — это отдельная,
    # обычная HTTP Basic Auth, см. protected!/authorized? выше). nil, если
    # гость или сессии нет.
    def current_user
      return @current_user if defined?(@current_user)

      @current_user = session[:user_id] && User.find_by(id: session[:user_id])
    end
  end

  helpers do
    def asset_path(path)
      # Находим путь к файлу в папке public
      file_path = File.join(settings.public_folder, path)
      
      if File.exist?(file_path)
        # Получаем метку времени редактирования файла в формате Unix Timestamp
        mtime = File.mtime(file_path).to_i
        "#{path}?v=#{mtime}"
      else
        path
      end
    end
  end




  # before ['/admin/ads*', '/admin/items*', '/admin/tags*', '/admin/import*'] do
  before ['/admin/*'] do
    protected!   
  end 

  # === end of auth ===

  # === start of timing ====
  before do 
    # $timing = []
  end  

  after do 
    # puts $timing.to_s
  end
  # === end of timing ====
  
  helpers InPlaceEditingHelpers
  helpers PaginateHelpers
  helpers PageTreeHelpers
  helpers TranslationHelpers
  helpers MiscHelpers
  helpers FeedAndSitemapHelpers
  helpers ProjectHelpers if defined?(ProjectHelpers)

  helpers Sinatra::ContentFor
  helpers Sinatra::FormHelpers  #https://stackoverflow.com/questions/12207161/good-forms-helpers-for-sinatra

  #https://github.com/nakajima/rack-flash
  # session_secret — постоянный, из config/secret.yml (settings.session_secret,
  # config_file уже вызвал set за нас) — без него Sinatra генерит случайный
  # секрет на каждую перезагрузку, и залогиненные слетают при каждом рестарте.
  enable :sessions
  use Rack::Flash, :sweep => true

  configure :development do |c|
    set :show_exceptions, true
    register Sinatra::Reloader
    also_reload './app.rb'
    also_reload './app/helpers/breadcrumb_helpers.rb'
    also_reload './app/helpers/in_place_editing_helpers.rb'
    also_reload './app/helpers/item_helpers.rb'
    also_reload './app/helpers/translation_helpers.rb'
    also_reload './project/helpers/project_helpers.rb'
    also_reload './project/routes.rb'
    after_reload do
      #puts '===reloaded============================'
    end
  end

  # https://stackoverflow.com/questions/12045495/activerecordconnectiontimeouterror-happening-sporadically
  after do
    ActiveRecord::Base.clear_active_connections!
  end 

  get '/admin/javascripts/pages-tree.js' do
    content_type 'application/javascript'
    send_file File.dirname(__FILE__) + '/app/javascripts/pages-tree.js'
  end

  get '/admin/javascripts/page-body-mentions.js' do
    content_type 'application/javascript'
    send_file File.dirname(__FILE__) + '/app/javascripts/page-body-mentions.js'
  end

  get '/admin/javascripts/pictures-form.js' do
    content_type 'application/javascript'
    send_file File.dirname(__FILE__) + '/app/javascripts/pictures-form.js'
  end

  get '/stats' do
    puts 'profiles Brand ' + Profile.where(profileable_type: 'Brand').count.to_s
    puts 'profiles Item ' + Profile.where(profileable_type: 'Item').count.to_s

    # Geoname.all.size.to_s
    # @countries = Geoname.where(feature_code: ["PCLF", "PCLI", "PCL", "PCLD", "TERR", "PCLS"]).order("name asc") #.size.to_s # ["PCL", "PCLD", "TERR"]
    # erb :"countries_geonames" #, :layout => :"/layout/gada_ads"
    "stats"
  end




  # запись кликов на кнопки ШАРЫ
  # require 'sinatra'
  # require 'json'
  # require 'time'
  # require 'fileutils'

  # Конфигурация пути к лог-файлу вне public/
  LOG_DIR  = File.join(settings.root, 'log')
  LOG_FILE = File.join(LOG_DIR, 'share-clicks.txt')

  # Автоматически создаем папку log/, если ее еще нет
  FileUtils.mkdir_p(LOG_DIR) unless File.directory?(LOG_DIR)

  # POST-обработчик кликов
  post '/api/log-share' do
    content_type :json

    data     = JSON.parse(request.body.read) rescue {}
    button   = data['button']   || 'unknown'
    page_url = (data['page_url'] || 'unknown').gsub("https://#{settings.domain}", '')
    country  = request.env['HTTP_CF_IPCOUNTRY'] || request.ip || 'Unknown'
    time     = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')

    # Форматируем CSV-строку
    log_line = "#{time}, #{button}, #{page_url}, #{country}\n"

    # Потокобезопасная запись в приватный файл
    File.open(LOG_FILE, 'a') do |f|
      f.flock(File::LOCK_EX)
      f.write(log_line)
    end

    { status: 'ok' }.to_json
  end

  # Защищенный маршрут для просмотра лога (только по секретному ключу)
  get '/admin/share-stats' do
    # Простейшая защита по токену в URL: /admin/share-stats?key=my_secret_key_123
    secret_key = "my_secret_key_123" 

    halt 403, "Access Denied" unless params[:key] == secret_key

    if File.exist?(LOG_FILE)
      content_type 'text/plain; charset=utf-8'
      File.read(LOG_FILE)
    else
      "Лог пока пуст."
    end
  end


  # Страница отчета
  get '/admin/reports/share-clicks' do
    @clicks = []
    @stats_by_button  = Hash.new(0)
    @stats_by_country = Hash.new(0)

    if File.exist?(LOG_FILE)
      File.readlines(LOG_FILE).reverse_each do |line|
        next if line.strip.empty?

        parts = line.strip.split(', ')
        next if parts.size < 4

        timestamp, button, page_url, country = parts

        @clicks << {
          time: timestamp,
          button: button,
          url: page_url,
          country: country
        }

        @stats_by_button[button] += 1
        @stats_by_country[country] += 1
      end
    end

    # Рендерим файл views/share-clicks.erb
    # erb :'share-clicks'
    erb :"/reports/share-clicks", layout: :"/layout/wide", views: settings.views_admin

  end


  # Приём HTML со страниц профилей от Chrome-расширения (?parse_profile=true
  # в URL включает отправку на стороне расширения). title/h1 достаём сразу —
  # они универсальны для любого сайта. Разбор labels (site-specific) сюда не
  # входит — планируется через AI по cleaned html_content, а не парсерами
  # под каждый сайт вручную.
  post '/api/parse' do
    content_type :json

    api_key = request.env['HTTP_X_API_KEY']
    unless api_key.to_s.strip == settings.api_key_for_parser.to_s.strip
      halt 401, { success: false, error: 'Unauthorized: Invalid or missing API Key' }.to_json
    end

    data = JSON.parse(request.body.read) rescue {}
    url  = data['url']
    html = data['html']

    halt 400, { success: false, error: 'html is required' }.to_json if html.to_s.empty?

    doc = Nokogiri::HTML(html)

    title = doc.at_css('title')&.text&.strip
    h1    = doc.at_css('h1')&.text&.strip

    # script/style/svg/comments — основной вес страницы (реклама, трекеры,
    # иконки), но не несут ни текста, ни структуры, нужной для будущего
    # разбора. Классы и теги вокруг реального контента остаются нетронутыми.
    doc.css('script, style, noscript, svg, link, meta, iframe').remove
    doc.xpath('//comment()').remove
    cleaned_html = doc.to_html

    profile = Profile.find_by(url: url)

    snap_shot = SnapShot.create!(
      profile_id: profile&.id,
      html_content: cleaned_html,
      param_1: title,
      param_2: h1,
      parsed: false
    )

    puts "=========================================="
    puts "ПОЛУЧЕН ЗАПРОС ДЛЯ ПРОФИЛЯ"
    puts "URL: #{url}"
    puts "Profile: #{profile ? profile.id : 'не найден по url'}"
    puts "title: #{title}"
    puts "h1: #{h1}"
    puts "Размер HTML: было #{html.length}, стало #{cleaned_html.length} символов"
    puts "=========================================="

    { status: 'ok', snap_shot_id: snap_shot.id, profile_id: profile&.id }.to_json
  end



end
