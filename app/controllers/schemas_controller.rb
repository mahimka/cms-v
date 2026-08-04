class SchemasController < App

  namespace '/admin' do

    get '/schemas' do

      @q = Schema.ransack(params[:q])
      @schemas_found = @q.result(distinct: true).size
      @schemas       = @q.result(distinct: true).order(:ancestry, :position, :name).page(params[:page]).per(100)

      erb :"/schemas/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/schemas/new' do
      if params[:parent_id]
        @schema = Schema.new(parent_id: params[:parent_id])
      else
        @schema = Schema.new
      end
      erb :"/schemas/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/schemas/:id' do
      @schema = Schema.find(params[:id])
      erb :"/schemas/show", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/schemas/:id/edit' do
      @schema = Schema.find(params[:id])
      erb :"/schemas/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/schemas' do
      @schema = Schema.new(params[:schema])
      if @schema.save
        assign_schema_tags_and_labels(@schema)
        flash[:notice] = "Schema created!"
        redirect '/admin/schemas'
      else
        flash.now[:error_title] = "Cannot create a new schema:"
        flash.now[:errors] = @schema.errors.full_messages
        erb :"/schemas/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/schemas/:id' do
      @schema = Schema.find(params[:id])
      if @schema.update(params[:schema])
        assign_schema_tags_and_labels(@schema)
        flash[:notice] = "Schema updated!"
        redirect "/admin/schemas/#{@schema.id}/edit"
      else
        flash.now[:error_title] = "Cannot update the schema:"
        flash.now[:errors] = @schema.errors.full_messages
        erb :"/schemas/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    delete '/schemas/:id' do
      @schema = Schema.find(params[:id])
      if @schema.destroy
        flash[:notice] = "Schema destroyed!"
        redirect '/admin/schemas'
      else
        flash[:error_title] = "Cannot destroy the schema:"
        flash[:errors] = @schema.errors.full_messages
        redirect '/admin/schemas'
      end
    end

  end

  private

  # Прямые (не унаследованные) теги и labels этого узла schema —
  # то, что реально хранится в schema_tags/schema_labels.
  def assign_schema_tags_and_labels(schema)
    schema.tag_ids   = Array(params[:tag_ids]).reject(&:blank?)
    schema.label_ids = Array(params[:label_ids]).reject(&:blank?)
  end

end
