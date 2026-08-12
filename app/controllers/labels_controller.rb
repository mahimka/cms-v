class LabelsController < App

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

    # Пересортировать детей группы по name — как строки ("string") или
    # как числа ("float", для лейблов вроде "0.01", "0.5", "3", "44").
    post '/labels/:id/sort_children' do
      group = Label.find(params[:id])
      children = group.children.to_a

      sorted = params[:by] == 'float' ? children.sort_by { |l| l.name.to_f } : children.sort_by { |l| l.name.to_s }

      sorted.each_with_index { |label, index| label.update_column(:position, index) }

      redirect back
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
