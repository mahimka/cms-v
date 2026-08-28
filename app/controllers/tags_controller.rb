class TagsController < App

  # Импортируемые поля тега/группы — без id, created_at, updated_at,
  # translations (см. /tags/import) и без parent_id (он всегда
  # пересчитывается программно, не берётся из файла).
  TAG_IMPORT_FIELDS = %w[active short short_2 admin_notes fixed position].freeze

  namespace '/admin' do

    get '/tags' do 

      @q = Tag.ransack(params[:q])
      @tags_found = @q.result(distinct: true).size # for index.rb
      @tags       = @q.result(distinct: true).includes(:parent).order(:parent_id, :position, :name).page(params[:page]).per(500)

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
      tags = Tag.where("name LIKE ? ESCAPE '\\'", "%#{escaped}%").order(:name).limit(20)

      tags.map { |t| { id: t.id, name: t.name } }.to_json
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

    # Пересортировать детей группы по name — как строки ("string") или
    # как числа ("float", для тегов вроде "0.01", "0.5", "3", "44").
    post '/tags/:id/sort_children' do
      group = Tag.find(params[:id])
      children = group.children.to_a

      sorted = params[:by] == 'float' ? children.sort_by { |t| t.name.to_f } : children.sort_by { |t| t.name.to_s }

      sorted.each_with_index { |tag, index| tag.update_column(:position, index) }

      redirect back
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
    # id/created_at/updated_at/translations сознательно не переносятся —
    # только TAG_IMPORT_FIELDS; поиск группы/тега — по name (уникален),
    # так что повторный импорт того же файла обновляет, а не дублирует.
    # parent_id детей всегда пересчитывается на актуальный id найденной/
    # созданной группы, а не на id из файла (он может уже не существовать).
    post '/tags/import' do
      upload = params[:import_file]
      halt 422, "Файл не выбран" unless upload.is_a?(Hash) && upload[:tempfile]

      data = JSON.parse(upload[:tempfile].read)

      group = Tag.find_or_initialize_by(name: data.fetch('name'))
      group.parent_id = nil
      group.assign_attributes(data.slice(*TAG_IMPORT_FIELDS))
      group.save!

      imported = Array(data['children']).map do |child_data|
        child = Tag.find_or_initialize_by(name: child_data.fetch('name'))
        child.parent_id = group.id
        child.assign_attributes(child_data.slice(*TAG_IMPORT_FIELDS))
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