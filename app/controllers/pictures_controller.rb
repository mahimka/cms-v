require 'fileutils'

class PicturesController < App

  IMAGEABLE_TYPES = %w[Entity Item Event].freeze

  # Ключ — класс для figure (см. project/views/profile_painting.erb),
  # значение — подпись в select. Полный список ratio-модификаторов Bulma
  # 1.0 (image element), другого источника этих классов в приложении нет.
  RATIOS = {
    "" => "— none —",
    "is-square" => "square (1:1)",
    "is-1by1" => "1:1",
    "is-5by4" => "5:4",
    "is-4by3" => "4:3",
    "is-3by2" => "3:2",
    "is-5by3" => "5:3",
    "is-16by9" => "16:9 (widescreen)",
    "is-2by1" => "2:1",
    "is-3by1" => "3:1",
    "is-4by5" => "4:5",
    "is-3by4" => "3:4",
    "is-2by3" => "2:3",
    "is-3by5" => "3:5",
    "is-9by16" => "9:16 (vertical widescreen)",
    "is-1by2" => "1:2",
    "is-1by3" => "1:3",
  }.freeze

  # Единственная схема, объединяющая группы тегов, которыми имеет смысл
  # помечать картинки (независимо от типа imageable) — см. Schema#effective_tags.
  TAGGABLE_SCHEMA_NAME = "Picture".freeze

  namespace '/admin' do

    get '/pictures' do

      @q = Picture.ransack(params[:q])
      @pictures_found = @q.result(distinct: true).size
      @pictures       = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(100)

      erb :"/pictures/index", layout: :"/layout/wide", views: settings.views_admin

    end

    get '/pictures/new' do
      @picture = Picture.new(imageable_type: params[:imageable_type], imageable_id: params[:imageable_id])
      erb :"/pictures/new", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/pictures/:id' do
      @picture = Picture.find(params[:id])
      erb :"/pictures/show", layout: :"/layout/wide", views: settings.views_admin
    end

    get '/pictures/:id/edit' do
      @picture = Picture.find(params[:id])
      erb :"/pictures/edit", layout: :"/layout/wide", views: settings.views_admin
    end

    post '/pictures' do
      picture_params, upload_error = process_picture_upload(params[:picture])
      @picture = Picture.new(picture_params)
      if upload_error
        flash.now[:error_title] = "Cannot process the uploaded image:"
        flash.now[:errors] = [upload_error]
        erb :"/pictures/new", layout: :"/layout/wide", views: settings.views_admin
      elsif @picture.save
        @picture.tag_ids = Array(params[:tag_ids]).reject(&:blank?)
        flash[:notice] = "Picture created!"
        redirect redirect_target_or(back_to_imageable_or('/admin/pictures'))
      else
        flash.now[:error_title] = "Cannot create a new picture:"
        flash.now[:errors] = @picture.errors.full_messages
        erb :"/pictures/new", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    patch '/pictures/:id' do
      @picture = Picture.find(params[:id])
      picture_params, upload_error = process_picture_upload(params[:picture])
      if upload_error
        flash.now[:error_title] = "Cannot process the uploaded image:"
        flash.now[:errors] = [upload_error]
        erb :"/pictures/edit", layout: :"/layout/wide", views: settings.views_admin
      elsif @picture.update(picture_params)
        @picture.tag_ids = Array(params[:tag_ids]).reject(&:blank?)
        flash[:notice] = "Picture updated!"
        redirect redirect_target_or("/admin/pictures/#{@picture.id}/edit")
      else
        flash.now[:error_title] = "Cannot update the picture:"
        flash.now[:errors] = @picture.errors.full_messages
        erb :"/pictures/edit", layout: :"/layout/wide", views: settings.views_admin
      end
    end

    post '/pictures/:id/translate_alt' do
      @picture = Picture.find(params[:id])
      content_type :json

      halt 422, { error: "alt is blank — enter alt text first" }.to_json if @picture.alt.blank?

      translations, errors = translate_missing_alt_languages(@picture)
      @picture.update!(translations: translations)
      { translations: translations, errors: errors }.to_json
    end

    delete '/pictures/:id' do
      @picture = Picture.find(params[:id])
      imageable = @picture.imageable
      if @picture.destroy
        flash[:notice] = "Picture destroyed!"
        redirect redirect_target_or(imageable ? "/admin/#{imageable.class.name.underscore.pluralize}/#{imageable.id}" : '/admin/pictures')
      else
        flash[:error_title] = "Cannot destroy the picture:"
        flash[:errors] = @picture.errors.full_messages
        redirect redirect_target_or('/admin/pictures')
      end
    end

  end

  private

  # После создания картинки удобнее вернуться на карточку imageable
  # (Entity/Item), откуда её и добавляли, чем на общий список.
  def back_to_imageable_or(fallback)
    return fallback if @picture.imageable.nil?

    "/admin/#{@picture.imageable.class.name.underscore.pluralize}/#{@picture.imageable.id}"
  end

  # Формы, встроенные прямо в edit-страницу Entity/Item, передают явный
  # redirect_to, чтобы после save/delete админ оставался на этой странице.
  # Принимаем только локальные /admin/* пути (защита от open redirect).
  def redirect_target_or(fallback)
    target = params[:redirect_to]
    target && target.start_with?('/admin/') ? target : fallback
  end

  # Если в форме реально выбран файл (picture[image]) — сохраняем его в
  # public/<folder>, читаем размеры/mime через MiniMagick и подставляем
  # получившиеся file/content_type/width/height в params для Picture.new/update.
  # Без выбранного файла просто пропускаем params как есть (правка метаданных
  # уже существующей картинки без переpivotа файла).
  # Возвращает [params, error_message] — error_message нужен только на неудаче.
  def process_picture_upload(picture_params)
    upload = picture_params && picture_params[:image]
    requested_folder = picture_params && picture_params[:folder]
    picture_params = picture_params ? picture_params.dup : {}
    picture_params.delete(:image)
    picture_params.delete(:folder)
    return [picture_params, nil] unless upload.is_a?(Hash) && upload[:tempfile]

    folder = '/' + requested_folder.to_s.sub(%r{\A/}, '').sub(%r{/\z}, '')
    folder = '/images' if folder == '/'

    filename = unique_upload_filename(folder, sanitize_upload_filename(upload[:filename]))
    disk_path = File.join(settings.public_folder, folder, filename)
    FileUtils.mkdir_p(File.dirname(disk_path))
    File.open(disk_path, 'wb') { |f| f.write(upload[:tempfile].read) }

    begin
      image = MiniMagick::Image.open(disk_path)
      raise "not a valid image file" unless image.valid?
      format = image.type
      width = image.width
      height = image.height
    rescue StandardError => e
      File.delete(disk_path) if File.exist?(disk_path)
      return [picture_params, e.message]
    end

    picture_params[:file] = "#{folder}/#{filename}"
    picture_params[:content_type] = "image/#{format.downcase}"
    picture_params[:width] = width
    picture_params[:height] = height
    [picture_params, nil]
  end

  def sanitize_upload_filename(filename)
    base = File.basename(filename.to_s).gsub(/[^\w.\-]+/, '-')
    base.presence || "upload-#{Time.now.to_i}"
  end

  # Как TaggableTranslationsBackfiller (app/models/taggable_translations_backfiller.rb),
  # но для одной записи и по кнопке: заполняет только пустые языки,
  # никогда не перезаписывает то, что уже введено вручную.
  def translate_missing_alt_languages(picture)
    gemini = GeminiClient.new(api_key: settings.gemini_api_key)
    translations = (picture.translations || {}).dup
    errors = {}
    target_langs = settings.languages.keys.map(&:to_s) - [settings.home_language.to_s]

    target_langs.each do |lang|
      next if translations[lang].present?

      begin
        translations[lang] = gemini.translate(picture.alt, from: settings.home_language, to: lang)
      rescue StandardError => e
        errors[lang] = e.message
      end
    end

    [translations, errors]
  end

  def unique_upload_filename(folder, filename)
    ext = File.extname(filename)
    base = File.basename(filename, ext)
    candidate = filename
    i = 1
    while File.exist?(File.join(settings.public_folder, folder, candidate))
      candidate = "#{base}-#{i}#{ext}"
      i += 1
    end
    candidate
  end

end
