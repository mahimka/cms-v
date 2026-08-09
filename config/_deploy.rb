@user           = 'deploy'
@domain         = '0.0.0.0'
@password       = 'password'
@repository     = 'git@github.com:mahimka/nearme.git'
@branch         = 'main'
@app_name       = 'app_project_name'
@deploy_to      = "/home/" + @user + "/" + @app_name


# список файлов лучше здесь а не в Rakefile, чтобы можно было и загружать и для уникального проекта 
@settings_files = [
  'config/config.yml',
  'config/secret.yml',
  'config/database.yml',
  # 'project/config/database_geoname.yml',
]

# @project_dirs = ['project/helpers/*.*',
#                  'project/tasks/*.*',
#                  'project/views/*.*'
# ]

task :default do
  puts "Hello World333!"
end



