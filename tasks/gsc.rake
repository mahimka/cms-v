namespace :gsc_stats do
  desc "Create the gsc_stats table (in db/gsc.db) with a unique index on [page, query, stat_date]"
  task :create_table do
    if GscRecord.connection.table_exists?(:gsc_stats)
      puts "gsc_stats already exists in #{GscRecord.connection.pool.db_config.database} — skipping"
    else
      GscRecord.connection.create_table :gsc_stats do |t|
        t.string  :page,        null: false
        t.string  :query,       null: false
        t.date    :stat_date,   null: false
        t.integer :clicks,      default: 0
        t.integer :impressions, default: 0
        t.float   :ctr
        t.float   :position
        t.timestamps
      end

      GscRecord.connection.add_index :gsc_stats, [:page, :query, :stat_date], unique: true, name: 'index_gsc_stats_on_page_query_date'

      puts "Created gsc_stats table + unique index in #{GscRecord.connection.pool.db_config.database}"
    end
  end

  desc "Create a schema.rb file for the stats database"
  task :schema_dump do
    # GscRecord уже подключён к db/gsc.db в app.rb — переустанавливать
    # соединение здесь нельзя, иначе Gsc.connection (та же самая, раз Gsc
    # наследует GscRecord) молча переключится на другую базу для всего
    # процесса, в том числе для gsc_stats:get_stats, если он выполнится следом.

    # Путь, куда сохранится схема
    schema_file = File.join(Dir.pwd, 'db', 'stats_schema.rb')
    
    File.open(schema_file, "w") do |file|
      ActiveRecord::SchemaDumper.dump(GscRecord.connection, file)
    end
    
    puts "Stats schema dumped to db/stats_schema.rb"
  end

  desc "получаю данные с gsc"  
  task :get_stats do 

    # require 'google/apis/searchconsole_v1'
    # require 'googleauth'
    # require 'date'
    # require 'json'

    # ====================== НАСТРОЙКИ ======================
    # SITE_URL            = 'sc-domain:diversorio.com'                # ← замени на свой сайт (с / в конце!)
    SITE_URL = App.settings.gsc_site_url                # ← замени на свой сайт (с / в конце!)
    # SITE_URL            = 'sc-domain:gambling-roulette.info'                # ← замени на свой сайт (с / в конце!)
    # SERVICE_ACCOUNT_FILE = './config/certs/diversorio-da7029024942.json'              # файл из Google Cloud (Service Account key)
    SERVICE_ACCOUNT_FILE = App.settings.gsc_service_account_file              # файл из Google Cloud (Service Account key)
    # =======================================================

    # Проверка файлов
    unless File.exist?(SERVICE_ACCOUNT_FILE)
      puts "Ошибка: Не найден #{SERVICE_ACCOUNT_FILE}!"
      puts "Скачай его из Google Cloud Console → IAM → Service Accounts → Keys → Add Key → JSON"
      exit 1
    end

    # Авторизация через Service Account (без браузера!)
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(SERVICE_ACCOUNT_FILE, 'r'),
      scope: 'https://www.googleapis.com/auth/webmasters.readonly'
    )

    authorizer.fetch_access_token!

    # Инициализация сервиса
    service = Google::Apis::SearchconsoleV1::SearchConsoleService.new
    service.authorization = authorizer

    # Запрос аналитики (исправлено: query_searchanalytic без 's'!)
    request = Google::Apis::SearchconsoleV1::SearchAnalyticsQueryRequest.new(
      # start_date: (Date.today - 90).iso8601,
      start_date: (Date.today - 4).iso8601,
      # end_date:   Date.today.iso8601,
      end_date:   (Date.today - 4).iso8601,
      dimensions: %w[page query date], #['query'], #  query page date   query, page, country, device, searchAppearance, date
      row_limit:  5000
    )

    begin
      puts "Получаем данные для #{SITE_URL} за последние 30 дней..."
      response = service.query_searchanalytic(SITE_URL, request)  # ← ВОТ ТУТ ИСПРАВЛЕНО!

      if response.rows.nil? || response.rows.empty?
        puts "Нет данных за этот период. Проверьте, добавлен ли сайт в GSC и есть ли трафик."
        exit 1
      end

      # results = response.rows.map do |row|
      #   {
      #     key_0:        row.keys[0],
      #     key_1:        row.keys[1],
      #     key_2:        row.keys[2],
      #     clicks:      row.clicks.to_i,
      #     impressions: row.impressions.to_i,
      #     ctr:         format('%.2f', row.ctr * 100),
      #     position:    format('%.1f', row.position)
      #   }
      # end.sort_by { |h| -h[:clicks] }

      # # Топ-20 в консоль
      # puts "\nТОП-20 запросов:\n\n"
      # results.first(20).each_with_index do |r, i|
      #   puts "#{i+1}. #{r[:clicks].to_s.rjust(6)} кликов | #{r[:ctr]}% CTR | поз. #{r[:position]} | #{r[:query]}"
      # end

      # # Сохранение в JSON
      # filename = "diversorio_gsc_page_query_#{Date.today.strftime('%Y-%m-%d')}.json"
      # File.write(filename, JSON.pretty_generate(results))
      # puts "\nГотово! #{results.size} строк сохранено в #{filename}"

      # Превращаем строки ответа Google API в массив хэшей для БД
      stats_to_insert = response.rows.map do |row|
        # Нормализация URL (если нужно оставить только путь без домена)
        raw_page_url = row.keys[0]
        normalized_path = URI.parse(raw_page_url).path rescue raw_page_url

        {
          page: normalized_path,
          query: row.keys[1],
          stat_date: row.keys[2], # Дата приходит строкой из GSC, ActiveRecord сам скастит в date
          clicks: row.clicks.to_i,
          impressions: row.impressions.to_i,
          ctr: row.ctr.to_f,
          position: row.position.to_f,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # Массовый Upsert
      if stats_to_insert.any?
        Gsc.upsert_all(
          stats_to_insert,
          unique_by: [:page, :query, :stat_date] # Поля составного уникального индекса
        )
        puts "Успешно сохранено/обновлено записей: #{stats_to_insert.size}"
      else
        puts "Нет данных для сохранения."
      end



    rescue Google::Apis::ClientError => e
      puts "Ошибка API (код: #{e.status_code}):"
      puts e.message
      puts "\nВозможные причины:"
      puts "• Сайт '#{SITE_URL}' не добавлен в Search Console или нет доступа."
      puts "• Нет данных за период (попробуйте увеличить диапазон дат)."
      puts "• Service Account не добавлен в GSC как пользователь (проверьте email вида 'name@project.iam.gserviceaccount.com')."
    rescue => e
      puts "Неожиданная ошибка: #{e.message}"
      puts e.backtrace.join("\n")
    end


    
  end

end