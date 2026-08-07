class ProfilesController < App

  PROFILEABLE_TYPES = %w[Entity Item Event].freeze

  namespace '/admin' do

    # index
    get '/profiles' do

      @q = Profile.ransack(params[:q])
      @profiles_found = @q.result(distinct: true) # for index.rb
      @profiles       = @q.result(distinct: true).page(params[:page]).per(100)

      erb :"/profiles/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/profiles/new' do
      @profile = Profile.new(profileable_type: params[:profileable_type], profileable_id: params[:profileable_id])
      erb :"/profiles/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/profiles/:id' do
      @profile = Profile.find(params[:id])
      erb :"/profiles/show", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/profiles/:id/edit' do
      @profile = Profile.find(params[:id])
      erb :"/profiles/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/profiles' do
      @profile = Profile.new(params[:profile])
      if @profile.save
        flash[:notice] = "Profile created!"
        redirect redirect_target_or(back_to_profileable_or('/admin/profiles'))
      else
        flash.now[:error_title] = "Cannot create a new profile:"
        flash.now[:errors] = @profile.errors.full_messages
        erb :"/profiles/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/profiles/:id' do
      @profile = Profile.find(params[:id])
      if @profile.update(params[:profile])
        flash[:notice] = "Profile updated!"
        redirect redirect_target_or("/admin/profiles/#{@profile.id}/edit")
      else
        flash.now[:error_title] = "Cannot update the profile:"
        flash.now[:errors] = @profile.errors.full_messages
        erb :"/profiles/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    delete '/profiles/:id' do
      @profile = Profile.find(params[:id])
      profileable = @profile.profileable
      if @profile.destroy
        flash[:notice] = "Profile destroyed!"
        redirect redirect_target_or(profileable ? "/admin/#{profileable.class.name.underscore.pluralize}/#{profileable.id}" : '/admin/profiles')
      else
        flash[:error_title] = "Cannot destroy the profile:"
        flash[:errors] = @profile.errors.full_messages
        redirect redirect_target_or('/admin/profiles')
      end
    end

  end

  private

  # После создания профиля удобнее вернуться на карточку profileable
  # (Entity/Item/Event), откуда его и добавляли, чем на общий список.
  def back_to_profileable_or(fallback)
    return fallback if @profile.profileable.nil?

    "/admin/#{@profile.profileable.class.name.underscore.pluralize}/#{@profile.profileable.id}"
  end

  # Формы, встроенные прямо в edit-страницу Entity/Item/Event (см.
  # entities/_profiles_fields.erb), передают явный redirect_to, чтобы после
  # save/delete админ оставался на этой странице. Принимаем только локальные
  # /admin/* пути, чтобы значением из формы нельзя было увести на внешний домен.
  def redirect_target_or(fallback)
    target = params[:redirect_to]
    target && target.start_with?('/admin/') ? target : fallback
  end

end
