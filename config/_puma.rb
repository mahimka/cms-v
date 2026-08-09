root = "#{Dir.getwd}"

bind "unix://#{root}/tmp/puma.sock"

pidfile "#{root}/tmp/puma.pid"

state_path "#{root}/tmp/puma.state"

rackup "#{root}/config.ru"

# Change to match your CPU core count
workers 2

# Min and Max threads per worker
threads 1, 2

environment 'production'

# activate_control_app