## двинуть в инвайронтмент??
require "sinatra/base" 
require 'sinatra/reloader'       
require "sinatra/config_file"
require "sinatra/content_for" 
require "sinatra/namespace"    


# перенес в environment.rb
# require_all 'app/helpers'
# require_all 'project/helpers'
# require_all 'lib' 

# module ProjectHelpers

#   # def path_to_item(item)
#   #   settings.items_folder + "/" + item.to_param.to_s +  " from app ProjectHelpers".to_s
#   # end   

# end  


Ancestry.default_ancestry_format = :materialized_path2


class App < Sinatra::Base    

  use Rack::MethodOverride

  # i test git bare


  # подключаю списки для стран и прочего, там - константы - маасивы стран
  # include AdsLists # константы для формироварния списков из /lib/Lists.rb
  
  register Sinatra::Namespace
  register Sinatra::ConfigFile

  config_file [
    "./config/config.yml", 
    "./config/secret.yml",
    # "./config/config_languages.yml", 
    # "./config/config_folders.yml", 
    # "./config/baza_objects.yml"
  ]
  
  configure do
    set :public_folder, 'public' 
    set :views_admin,   File.dirname(__FILE__) + '/app/views/admin' 
    set :views_project, File.dirname(__FILE__) + '/project/views'
    set :views, File.dirname(__FILE__) + '/app/views' 

    # enable :logging
    set :show_exceptions, :after_handler
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
  end  

  # === start of view rendering helpers (project/views -> app/views с фолбэком) ===

  helpers do
    def call_erb_view(view, layout: "default.erb")
      view = view.to_s
      layout = layout.to_s

      # 1. Поиск шаблона страницы (view): project/views -> app/views -> app/views/default.erb
      view_path = [
        (File.join(settings.views_project, view) unless view.empty?),
        (File.join(settings.views, view) unless view.empty?),
        File.join(settings.views, "default.erb")
      ].compact.find { |file| File.file?(file) }

      # 2. Поиск макета (layout): project/views/layout -> app/views/layout -> app/views/layout/default.erb
      layout_path = [
        (File.join(settings.views_project, "layout", layout) unless layout.empty?),
        (File.join(settings.views, "layout", layout) unless layout.empty?),
        File.join(settings.views, "layout", "default.erb")
      ].compact.find { |file| File.file?(file) }

      # Защита: если даже app/views/default.erb не существует
      unless view_path
        raise Errno::ENOENT, "Шаблон '#{view}' не найден ни в project/views, ни в app/views (включая default.erb)"
      end

      # 3. Передаем абсолютный путь БЕЗ расширения .erb как символ (Symbol)
      # Удаляем .erb с конца пути, так как Sinatra сама добавляет расширение
      view_sym = view_path.sub(/\.erb$/, '').to_sym

      if layout_path
        layout_sym = layout_path.sub(/\.erb$/, '').to_sym
        # Важно:views: "/" говорит Sinatra брать абсолютные пути от корня системы
        erb view_sym, layout: layout_sym, views: "/"
      else
        erb view_sym, layout: false, views: "/"
      end
    end

    def partial(partial_file, options = {})
      # Формируем список кандидатов на поиск
      # Порядок: project/views/partials/file.erb -> app/views/partials/file.erb
      partial_path = [
        File.join(settings.views_project, "partials", "#{partial_file}.erb"),
        File.join(settings.views, "partials", "#{partial_file}.erb")
      ].compact.find { |file| File.exist?(file) }

      # Если паршел не найден ни в одной из папок
      unless partial_path
        raise Errno::ENOENT, "Паршел '#{partial_file}' не найден ни в project/views/partials, ни в app/views/partials"
      end

      # Преобразуем абсолютный путь в символ без расширения .erb
      partial_sym = partial_path.sub(/\.erb$/, '').to_sym

      # Рендерим без layout и передаем локальные переменные
      erb partial_sym, layout: false, views: "/", locals: options
    end
  end

  # === end of view rendering helpers ===

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
  

  # helpers BreadcrumbHelpers
  helpers InPlaceEditingHelpers
  helpers PaginateHelpers
  helpers PageTreeHelpers
  helpers TranslationHelpers
  # helpers Kaminari::Helpers::SinatraHelpers
  # helpers ItemHelpers

  # helpers ProjectHelpers # !!!!!!!!!!!!!!! проверь, работает ли!! (лежит в папке /project)

  helpers Sinatra::ContentFor
  helpers Sinatra::FormHelpers  #https://stackoverflow.com/questions/12207161/good-forms-helpers-for-sinatra

  #https://github.com/nakajima/rack-flash
  enable :sessions  
  use Rack::Flash, :sweep => true  
  #set :session_secret, "secret"  # нужен секрет али нет?? где читать ?

  configure :development do |c|
    register Sinatra::Reloader
    also_reload './app.rb'
    also_reload './app/helpers/breadcrumb_helpers.rb'
    also_reload './app/helpers/in_place_editing_helpers.rb'
    also_reload './app/helpers/item_helpers.rb'
    also_reload './app/helpers/translation_helpers.rb'
    also_reload './project/helpers/project_helpers.rb'
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

  get '/stats' do
    puts 'profiles Brand ' + Profile.where(profileable_type: 'Brand').count.to_s
    puts 'profiles Item ' + Profile.where(profileable_type: 'Item').count.to_s


    # Geoname.all.size.to_s
    # @countries = Geoname.where(feature_code: ["PCLF", "PCLI", "PCL", "PCLD", "TERR", "PCLS"]).order("name asc") #.size.to_s # ["PCL", "PCLD", "TERR"]
    # erb :"countries_geonames" #, :layout => :"/layout/gada_ads"
    "stats"
  end





end
