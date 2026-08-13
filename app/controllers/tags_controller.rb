class TagsController < App

  namespace '/admin' do 

    get '/tags' do 

      @q = Tag.ransack(params[:q])
      @tags_found = @q.result(distinct: true).size # for index.rb
      @tags       = @q.result(distinct: true).includes(:parent).order(:parent_id, :position, :name).page(params[:page]).per(500)

      # Один запрос на всю страницу вместо tag.usage_count на каждую строку.
      @tagging_counts_by_tag = Tagging.group(:tag_id).count

      erb :"/tags/index", layout: :"/layout/wide", views: settings.views_admin

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