## двинуть в инвайронтмент??
require "sinatra/base" 
require 'sinatra/reloader'       
require "sinatra/config_file"
require "sinatra/content_for" 
require "sinatra/namespace"    

Ancestry.default_ancestry_format = :materialized_path2

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
    set :public_folder, 'public' 
    set :views_admin,   File.dirname(__FILE__) + '/app/views/admin' 
    set :views_project, File.dirname(__FILE__) + '/project/views'
    set :views, File.dirname(__FILE__) + '/app/views' 
    set :show_exceptions, :after_handler
    # enable :logging
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
  helpers ProjectHelpers

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

  get '/stats' do
    puts 'profiles Brand ' + Profile.where(profileable_type: 'Brand').count.to_s
    puts 'profiles Item ' + Profile.where(profileable_type: 'Item').count.to_s

    # Geoname.all.size.to_s
    # @countries = Geoname.where(feature_code: ["PCLF", "PCLI", "PCL", "PCLD", "TERR", "PCLS"]).order("name asc") #.size.to_s # ["PCL", "PCLD", "TERR"]
    # erb :"countries_geonames" #, :layout => :"/layout/gada_ads"
    "stats"
  end


end
