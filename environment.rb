# https://blazarblogs.wordpress.com/2019/07/27/mvc-architecture-with-sinatra/amp/

# require 'rubygems'
# require 'bundler'
require 'bundler/setup'

APP_ENV = ENV['RACK_ENV'] || "development"

Bundler.require :default, APP_ENV.to_sym

# путь до public/ вне Sinatra-контекста (например из моделей, где settings
# недоступен) — Picture#sync_exif_metadata им пользуется.
PUBLIC_FOLDER = File.expand_path('public', __dir__)

# mini_exiftool по умолчанию ищет exiftool в PATH (нужен apt-get на сервере) -
# exiftool_vendored тащит сам бинарник внутри гема, просто указываем на него.
MiniExiftool.command = ExiftoolVendored.path_to_exiftool


# файлы с именем, начинающимся на "_", не подключаются автоматически -
# используй такой префикс, чтобы просто хранить код в проекте, не запуская его
def require_all_except_underscored(dir)
  files = Dir.glob(File.join(dir, '**', '*.rb')).reject { |f| File.basename(f).start_with?('_') }
  require_all files
end

require_all './app/helpers'
require_relative './app'

# project/routes.rb грузится РАНЬШЕ app/controllers/routes_controller.rb -
# Sinatra при диспетчеризации берёт первый подходящий маршрут, так что
# одноимённые роуты из project/routes.rb перекрывают дефолтные, а не
# наоборот (как это было бы при обычном порядке project после app)
require_relative './project/routes.rb' if File.exist?('./project/routes.rb')

require_all_except_underscored 'app'
require_all_except_underscored 'lib'
require_all_except_underscored 'project'

# ActiveSupport::Inflector.inflections do |inflect|
#   # inflect.irregular 'bonus', 'bonuses'
# end

# fffffffff