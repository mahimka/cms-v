class TagsController < App

  # Импортируемые поля тега/группы — без id, created_at, updated_at
  # и без parent_id (он всегда пересчитывается программно, не берётся
  # из файла). translations/icon_svg — как у LABEL_IMPORT_FIELDS
  # (см. labels_controller.rb), чтобы экспорт/импорт между проектами
  # переносил переводы и иконки, а не только базовые поля.
  TAG_IMPORT_FIELDS = %w[active short short_2 admin_notes fixed position translations icon_svg].freeze

  namespace '/admin' do

    get '/tags' do 

      @q = Tag.ransack(params[:q])
      @tags_found = @q.result(distinct: true).size # for index.rb
      # per(5000): группировка на странице собирается из @tags целиком (см.
      # index.erb) — если родитель и дети разъедутся по разным страницам
      # пагинации (легко происходит для новых групп с большим id, т.к.
      # сортировка по parent_id — числовая, не по смыслу), группа рисуется
      # "пустой". Тегов сильно меньше 5000, так что пагинация тут по факту
      # не нужна — просто держим всё на одной странице.
      @tags       = @q.result(distinct: true).includes(:parent).order(:parent_id, :position, :name).page(params[:page]).per(5000)

      # Один запрос на всю страницу вместо tag.usage_count на каждую строку.
      @tagging_counts_by_tag = Tagging.group(:tag_id).count

      erb :"/tags/index", layout: :"/layout/wide", views: settings.views_admin

    end  

    # Поиск тегов по имени для JS-автокомплита (см. markers/index.erb —
    # привязка Marker к Tag). До /tags/:id, иначе "search" перехватится
    # как :id.
    get '/tags/search' do
      content_type :json

      query = params[:q].to_s.strip
      halt 200, [].to_json if query.length < 2

      escaped = query.gsub(/[%_]/) { |c| "\\#{c}" }
      tags = Tag.includes(:parent).where("name LIKE ? ESCAPE '\\'", "%#{escaped}%").order(:name).limit(20)

      tags.map { |t| { id: t.id, name: t.name, parent: t.parent&.name, usage_count: t.usage_count } }.to_json
    end

    get '/tags/new' do
      if params[:name]
        @tag = Tag.new(name: params[:name], short: params[:short], parent_id: params[:parent_id])
      elsif params[:parent_id]  
        @tag = Tag.new(parent_id: params[:parent_id])
      else
        @tag = Tag.new
      end
      erb :"/tags/new", layout: :"/layout/wide", views: settings.views_admin
    end 

    get '/tags/:id' do

      @tag = Tag.find(params[:id])
      @taggings = @tag.taggings.includes(:taggable).order(:taggable_type)

      erb :"/tags/show", layout: :"/layout/wide", views: settings.views_admin

    end

    # edit
    get '/tags/:id/edit' do 
      @tag = Tag.find(params[:id])
      erb :"/tags/edit", layout: :"/layout/wide", views: settings.views_admin
    end 
    
    # create
    post '/tags' do 
      @tag = Tag.new(params[:tag])
      if @tag.save
        flash[:notice] = "Tag created!!"
        #redirect "tags/#{@tag.id}/edit"
        redirect ('admin/tags')
      else
        flash.now[:error_title] = "Cannot create a new tag:"
        flash.now[:errors] = @tag.errors.full_messages 
        erb :"/tags/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    # update
    patch '/tags/:id' do
      @tag = Tag.find(params[:id])
      if @tag.update(params[:tag])
        flash[:notice] = "Tag updated!"
        # redirect "/admin/tags/#{@tag.id}/edit"  
        redirect back #{}"/admin/tags/#{@tag.id}/edit" 
      else
        flash[:error_title] = "Cannot update the tag:"
        flash[:errors] = @tag.errors.full_messages 
        erb :"/tags/edit", layout: :"/layout/wide", views: settings.views_admin
        #redirect '/tags/'+ @tag.id.to_s + '/edit'
      end  
      
    end

    # Переводит name тега на все языки, для которых в translations ещё
    # нет значения (уже заполненные вручную — не трогает), одним вызовом
    # Gemini на все недостающие языки сразу (см.
    # GeminiClient#translate_to_languages — тот же приём, что у кнопки
    # "перевести на все" у Page, но здесь один record = один hash со
    # всеми языками, а не отдельная запись на каждый).
    #
    # source language — "en", не settings.home_language ("sl")! name у
    # Tag/Label заведён по-английски (в отличие от Page, где sl — основной
    # язык сайта) — исключать sl из целей было багом: словенский перевод
    # никогда не генерировался.
    post '/tags/:id/translate_missing_languages' do
      tag = Tag.find(params[:id])
      content_type :json

      missing_langs = settings.languages.keys.map(&:to_s) - ['en']
      missing_langs = missing_langs.select { |lang| tag.translations&.dig(lang).blank? }

      halt 200, [].to_json if missing_langs.empty?

      # Если translations['en'] уже заполнен вручную человеческим текстом —
      # переводим его, а не сырое name (см. аналогичный /labels/:id/...).
      source_text = tag.translations&.dig('en').presence || tag.name

      client = GeminiClient.new(api_key: settings.gemini_api_key)
      translated = client.translate_to_languages(source_text, from: 'en', to: missing_langs)
      tag.update!(translations: (tag.translations || {}).merge(translated))

      missing_langs.map { |lang| { lang: lang, ok: translated[lang].present?, value: translated[lang] } }.to_json
    rescue StandardError => e
      halt 422, [{ lang: nil, ok: false, error: e.message }].to_json
    end

    # Пересортировать детей группы по name — как строки ("string") или
    # как числа ("float", для тегов вроде "0.01", "0.5", "3", "44").
    post '/tags/:id/sort_children' do
      group = Tag.find(params[:id])
      children = group.children.to_a

      sorted = params[:by] == 'float' ? children.sort_by { |t| t.name.to_f } : children.sort_by { |t| t.name.to_s }

      sorted.each_with_index { |tag, index| tag.update_column(:position, index) }

      redirect back
    end

    # Слить source в target: все taggings/markers/schema_tags source
    # переезжают на target (дубли, если объект уже помечен обоими —
    # схлопываются, не плодятся — на taggings/schema_tags есть unique index
    # на комбинацию), затем source удаляется. fixed source нельзя — на него
    # могут ссылаться List#conditions по имени (см. FixedName). Тег с
    # детьми нельзя — PreventDestroyWithChildren всё равно не даст
    # destroy, а тут даём понятную ошибку заранее, а не после переноса тегов.
    post '/tags/:id/merge' do
      content_type :json

      source = Tag.find(params[:id])
      target = Tag.find(params[:target_tag_id])

      halt 422, { success: false, error: 'Нельзя сливать fixed тег' }.to_json if source.fixed?
      halt 422, { success: false, error: 'Нельзя слить тег сам с собой' }.to_json if source.id == target.id
      halt 422, { success: false, error: "У тега есть дочерние теги (#{source.children.pluck(:name).join(', ')}) — сначала перепривяжите их" }.to_json if source.children.any?

      ActiveRecord::Base.transaction do
        source.taggings.find_each do |tagging|
          if Tagging.exists?(tag_id: target.id, taggable_type: tagging.taggable_type, taggable_id: tagging.taggable_id)
            tagging.destroy
          else
            tagging.update!(tag_id: target.id)
          end
        end

        source.markers.update_all(tag_id: target.id)

        source.schema_tags.find_each do |schema_tag|
          if SchemaTag.exists?(tag_id: target.id, schema_id: schema_tag.schema_id)
            schema_tag.destroy
          else
            schema_tag.update!(tag_id: target.id)
          end
        end

        source.destroy!
      end

      { success: true, target_tag_id: target.id }.to_json
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
      halt 422, { success: false, error: e.message }.to_json
    end

    # Выгружает группу тегов (все колонки самой группы + все колонки
    # каждого вложенного тега в children) в public/<имя группы>.json.
    post '/tags/:id/export' do
      group = Tag.find(params[:id])
      data = group.attributes.merge('children' => group.children.map(&:attributes))
      filename = "#{group.name.parameterize}.json"
      File.write(File.join(settings.public_folder, filename), JSON.pretty_generate(data))

      flash[:notice] = "Exported '#{group.name}' (#{group.children.size} tags) to /#{filename}"
      redirect back
    end

    # Импорт группы + детей из файла, выгруженного /tags/:id/export.
    # id/created_at/updated_at сознательно не переносятся — только
    # TAG_IMPORT_FIELDS; поиск группы/тега — по name (уникален), так что
    # повторный импорт того же файла обновляет, а не дублирует.
    # parent_id детей всегда пересчитывается на актуальный id найденной/
    # созданной группы, а не на id из файла (он может уже не существовать).
    # translations — не replace, а merge_translations: пустой/частичный
    # набор языков в файле-источнике не затирает то, что уже переведено
    # на этой стороне (см. misc_helpers.rb#merge_translations).
    post '/tags/import' do
      upload = params[:import_file]
      halt 422, "Файл не выбран" unless upload.is_a?(Hash) && upload[:tempfile]

      data = JSON.parse(upload[:tempfile].read)

      group = Tag.find_or_initialize_by(name: data.fetch('name'))
      group.parent_id = nil
      group.assign_attributes(data.slice(*(TAG_IMPORT_FIELDS - %w[translations])))
      group.translations = merge_translations(group.translations, data['translations'])
      group.save!

      imported = Array(data['children']).map do |child_data|
        child = Tag.find_or_initialize_by(name: child_data.fetch('name'))
        child.parent_id = group.id
        child.assign_attributes(child_data.slice(*(TAG_IMPORT_FIELDS - %w[translations])))
        child.translations = merge_translations(child.translations, child_data['translations'])
        child.save!
        child
      end

      flash[:notice] = "Imported '#{group.name}' + #{imported.size} tags"
      redirect '/admin/tags'
    rescue StandardError => e
      flash[:error_title] = "Import failed:"
      flash[:errors] = [e.message]
      redirect '/admin/tags'
    end

    # delete
    delete '/tags/:id' do
      set_tag
      if @tag.destroy
        flash[:notice] = "Tag destroyed!"
        redirect '/admin/tags'
      else
        flash[:error_title] = "Cannot destroy the tag:"
        flash[:errors] = @tag.errors.full_messages 
        redirect '/tags'

      end

    end

  end

end