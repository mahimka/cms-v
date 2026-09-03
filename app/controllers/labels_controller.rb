class LabelsController < App

  # Импортируемые поля — без id, created_at, updated_at, ancestry (см.
  # /labels/import). ancestry не входит — иерархия пересчитывается
  # программно через parent=, id из файла мог не совпасть с id в текущей
  # базе (тот же приём, что у /schemas/import).
  LABEL_IMPORT_FIELDS = %w[translations field_type position active fixed icon_svg].freeze

  namespace '/admin' do

    get '/labels' do

      @q = Label.ransack(params[:q])
      @labels_found = @q.result(distinct: true).size
      @labels       = @q.result(distinct: true).order(:ancestry, :position, :name).page(params[:page]).per(500)

      # Один запрос на всю страницу вместо label.usage_count на каждую строку.
      @detail_counts_by_label = Detail.group(:label_id).count

      erb :"/labels/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/labels/new' do
      if params[:parent_id]
        @label = Label.new(parent_id: params[:parent_id])
      else
        @label = Label.new
      end
      erb :"/labels/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/labels/:id' do
      @label = Label.find(params[:id])
      erb :"/labels/show", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/labels/:id/edit' do
      @label = Label.find(params[:id])
      erb :"/labels/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/labels' do
      @label = Label.new(params[:label])
      if @label.save
        flash[:notice] = "Label created!"
        redirect '/admin/labels'
      else
        flash.now[:error_title] = "Cannot create a new label:"
        flash.now[:errors] = @label.errors.full_messages
        erb :"/labels/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/labels/:id' do
      @label = Label.find(params[:id])
      if @label.update(params[:label])
        flash[:notice] = "Label updated!"
        redirect "/admin/labels/#{@label.id}/edit"
      else
        flash.now[:error_title] = "Cannot update the label:"
        flash.now[:errors] = @label.errors.full_messages
        erb :"/labels/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    # Переводит name лейбла на все языки, для которых в translations ещё
    # нет значения — см. аналогичный /tags/:id/translate_missing_languages.
    #
    # source language — "en", не settings.home_language ("sl")! name у
    # Tag/Label заведён по-английски (в отличие от Page, где sl — основной
    # язык сайта) — исключать sl из целей было багом: словенский перевод
    # никогда не генерировался (см. отчёт по /labels/1082).
    post '/labels/:id/translate_missing_languages' do
      label = Label.find(params[:id])
      content_type :json

      missing_langs = settings.languages.keys.map(&:to_s) - ['en']
      missing_langs = missing_langs.select { |lang| label.translations&.dig(lang).blank? }

      halt 200, [].to_json if missing_langs.empty?

      # name у части labels — технический snake_case-ключ ("_whats_included"),
      # а не человеческий текст — если для него уже есть human-написанный
      # translations['en'] ("What's included"), переводим его, а не сырой key.
      source_text = label.translations&.dig('en').presence || label.name

      client = GeminiClient.new(api_key: settings.gemini_api_key)
      translated = client.translate_to_languages(source_text, from: 'en', to: missing_langs)
      label.update!(translations: (label.translations || {}).merge(translated))

      missing_langs.map { |lang| { lang: lang, ok: translated[lang].present?, value: translated[lang] } }.to_json
    rescue StandardError => e
      halt 422, [{ lang: nil, ok: false, error: e.message }].to_json
    end

    # Пересортировать детей группы по name — как строки ("string") или
    # как числа ("float", для лейблов вроде "0.01", "0.5", "3", "44").
    post '/labels/:id/sort_children' do
      group = Label.find(params[:id])
      children = group.children.to_a

      sorted = params[:by] == 'float' ? children.sort_by { |l| l.name.to_f } : children.sort_by { |l| l.name.to_s }

      sorted.each_with_index { |label, index| label.update_column(:position, index) }

      redirect back
    end

    # Выгружает все labels (все колонки) одним файлом в public/labels.json.
    post '/labels/export' do
      data = Label.all.map(&:attributes)
      File.write(File.join(settings.public_folder, 'labels.json'), JSON.pretty_generate(data))

      flash[:notice] = "Exported #{data.size} labels to /labels.json"
      redirect '/admin/labels'
    end

    # Импорт из файла, выгруженного /labels/export. id/created_at/updated_at
    # не переносятся; поиск — по name (уникален), так что повторный импорт
    # того же файла обновляет существующие записи, а не дублирует их.
    # Иерархия (ancestry) восстанавливается через parent= по имени родителя,
    # а не по старому id — обрабатываем родителей раньше детей (сортировка
    # по фактической глубине ancestry в файле).
    post '/labels/import' do
      upload = params[:import_file]
      halt 422, "Файл не выбран" unless upload.is_a?(Hash) && upload[:tempfile]

      records = JSON.parse(upload[:tempfile].read)
      records = records.sort_by { |r| r['ancestry'].to_s.split('/').reject(&:blank?).size }

      old_id_to_new = {}

      records.each do |r|
        old_parent_id = r['ancestry'].to_s.split('/').reject(&:blank?).last&.to_i
        new_parent = old_parent_id ? old_id_to_new[old_parent_id] : nil

        label = Label.find_or_initialize_by(name: r.fetch('name'))
        label.parent = new_parent
        label.assign_attributes(r.slice(*LABEL_IMPORT_FIELDS))
        label.save!

        old_id_to_new[r['id']] = label
      end

      flash[:notice] = "Imported #{records.size} labels"
      redirect '/admin/labels'
    rescue StandardError => e
      flash[:error_title] = "Import failed:"
      flash[:errors] = [e.message]
      redirect '/admin/labels'
    end

    delete '/labels/:id' do
      @label = Label.find(params[:id])
      if @label.destroy
        flash[:notice] = "Label destroyed!"
        redirect '/admin/labels'
      else
        flash[:error_title] = "Cannot destroy the label:"
        flash[:errors] = @label.errors.full_messages
        redirect '/admin/labels'
      end
    end

  end

end
