class PublicPhotosController < App

  helpers PictureUploadHelpers

  # Клиент должен был сжать фото сам (см. public/javascripts/photo-upload.js —
  # цель 130-160 КБ, потолок 200 КБ); это лишь подстраховка на случай
  # выключенного JS/старого браузера, а не второй пайплайн сжатия.
  MAX_UPLOAD_BYTES = 2 * 1024 * 1024

  post '/photos' do
    content_type :json

    imageable_type = params[:picture][:imageable_type]
    imageable_id   = params[:picture][:imageable_id]
    imageable = PicturesController::IMAGEABLE_TYPES.include?(imageable_type) &&
                imageable_type.safe_constantize&.find_by(id: imageable_id)

    # Имя файла — из названия объекта, к которому привязывается фото (а не
    # случайное "photo.jpg" от клиента); совпадение имени сам разрулит
    # unique_upload_filename в PictureUploadHelpers, добавив -1, -2...
    picture_params, upload_error = process_picture_upload(
      params[:picture], max_bytes: MAX_UPLOAD_BYTES, preferred_filename: imageable&.name
    )
    halt 422, { error: upload_error }.to_json if upload_error

    picture = Picture.new(
      picture_params.merge(
        imageable_type: imageable ? imageable_type : nil,
        imageable_id: imageable ? imageable_id : nil,
        published: false,
        user_id: current_user&.id,
        latitude: params[:picture][:latitude].presence,
        longitude: params[:picture][:longitude].presence,
        taken_at: parse_exif_taken_at(params[:picture][:taken_at])
      )
    )

    if picture.save
      { ok: true }.to_json
    else
      halt 422, { error: picture.errors.full_messages.join(", ") }.to_json
    end
  end

  private

  # EXIF DateTimeOriginal — "YYYY:MM:DD HH:MM:SS" (двоеточия и в дате —
  # так исторически сложилось в спецификации EXIF), Time.parse его не берёт.
  def parse_exif_taken_at(value)
    return nil if value.blank?

    Time.strptime(value, "%Y:%m:%d %H:%M:%S")
  rescue ArgumentError
    nil
  end

end
