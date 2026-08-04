@user           = 'deploy'
@domain         = '0.0.0.0'
@password       = 'password'
@repository     = 'git@github.com:mahimka/nearme.git'
@branch         = 'main'
@app_name       = 'app_project_name'
@deploy_to      = "/home/" + @user + "/" + @app_name

@settings_files = ['project/config/config.yml',
                   'project/config/secret.yml',
                   'project/config/database.yml',
                   'project/config/database_geoname.yml',
]

# @project_dirs = ['project/helpers/*.*',
#                  'project/tasks/*.*',
#                  'project/views/*.*'
# ]

task :default do
  puts "Hello World333!"
end



