# https://blazarblogs.wordpress.com/2019/07/27/mvc-architecture-with-sinatra/amp/

# require 'rubygems'
# require 'bundler'
require 'bundler/setup'

APP_ENV = ENV['RACK_ENV'] || "development"

Bundler.require :default, APP_ENV.to_sym


# файлы с именем, начинающимся на "_", не подключаются автоматически -
# используй такой префикс, чтобы просто хранить код в проекте, не запуская его
def require_all_except_underscored(dir)
  files = Dir.glob(File.join(dir, '**', '*.rb')).reject { |f| File.basename(f).start_with?('_') }
  require_all files
end

require_all './app/helpers'
require_relative './project/helpers/project_helpers'
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