class AdminController < App
 
  namespace '/admin' do

    get '/' do 
      erb :"index", layout: :"/layout/wide", views: settings.views_admin
    end

  end  


 # для всех хелперов in_place_
 get '/admin/:table_name/:object_id/ajax' do 

    model = Object.const_get(params[:table_name].classify)
    object = model.find(params[:object_id]) 
    column_name = (params.keys - ["object_id"]).first

    # begin
    #   "saved" if object.update_column(column_name, params[column_name]) && object.touch 
    # rescue StandardError => e
    #   puts e.message
    # end

    # по совету gemini переделвл чтобы был callback 
    begin
      # Присваиваем новое значение колонке
      object.assign_attributes(column_name => params[column_name])
      
      # Сохраняем. validate: false пропускает валидации, но ЗАПУСКАЕТ все коллбеки (after_save)!
      if object.save #(validate: false) && object.touch
        "saved"
      end
    rescue StandardError => e
      puts e.message
    end



  end





end

