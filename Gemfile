source 'https://rubygems.org'

gem "base64"       # your current problem
gem "csv"          # very common in Rails/Jekyll apps
gem "bigdecimal"   # appears in many money/decimal calculations
# gem "mutex_m"      # less common, but sometimes used
# gem "ostruct"      # will be gone in Ruby 3.5/4.0

gem 'mutex_m'
gem 'benchmark'

gem 'sinatra', require: 'sinatra/base'

#https://stackoverflow.com/questions/20638136/undefined-method-desc-for-sinatraapplicationclass
gem 'sinatra-contrib', require: false #'sinatra/contrib'

gem 'require_all'
gem "rack-flash3", require: 'rack-flash'

gem "sqlite3", "~> 1.4"

gem 'activerecord', '6.1.0', require: 'active_record'
gem 'sinatra-activerecord', require: 'sinatra/activerecord'


# NameError: uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger
gem 'concurrent-ruby', '1.3.4' 

# gem 'activesupport', require: 'active_support/inflector'

gem 'bcrypt', require: 'bcrypt'
# gem 'pundit', require: 'pundit'
# gem 'sinatra-pundit', require: 'sinatra/pundit'ctor'

gem "rake"

gem 'require_all'
gem "rack-flash3", require: 'rack-flash'

gem 'ancestry'
gem 'geocoder'
gem 'kaminari', require: 'kaminari'
gem 'ransack', require: 'ransack'
gem 'kramdown', require: 'kramdown'

gem 'ferrum'
gem "nokogiri"

gem 'mini_magick'

# запись author/title/GPS/даты из Picture обратно в EXIF файла (Picture#sync_exif_metadata) -
# exiftool_vendored тащит сам бинарник exiftool внутри гема (не нужен apt-get на сервере),
# mini_exiftool даёт удобный Ruby-API для записи поверх него (см. environment.rb)
gem 'exiftool_vendored'
gem 'mini_exiftool'

gem 'sinatra-formhelpers-ng', require: 'sinatra/form_helpers'
# gem 'acts-as-taggable-on', require: 'acts-as-taggable-on'

gem 'puma'

gem 'whenever', require: false

# for ajpes communications
gem 'savon'
gem 'dotenv'
gem 'retryable'
gem 'dry-schema'        # основной для Params
gem 'dry-validation'    # если захочешь позже Contract + rules
gem 'openssl'  # ← добавить

gem 'google-apis-searchconsole_v1'
gem 'googleauth'  

gem 'chartkick'

group :development do
  gem 'sinatra-contrib', require: 'sinatra/reloader'
  gem 'net-scp', '4.0.0'
  # gem 'net-ssh', '7.0.1'
  gem 'net-sftp', '4.0.0'
  gem 'byebug'
  gem 'colorize'
  gem 'pry'
  gem 'rubocop', require: false
  gem 'net-ssh', '>= 6.0.2'
  gem 'ed25519', '>= 1.2', '< 2.0'
  gem 'bcrypt_pbkdf', '>= 1.0', '< 2.0'
end

# gem 'bcrypt', require: 'bcrypt'
# gem 'pundit', require: 'pundit'
# gem 'sinatra-pundit', require: 'sinatra/pundit'