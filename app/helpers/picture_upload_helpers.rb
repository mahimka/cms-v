require 'fileutils'

# Обработка загруженного файла картинки — общая для админского
# PicturesController и публичного PublicPhotosController (см.
# app/controllers/public_photos_controller.rb).
module PictureUploadHelpers

  # Если в форме реально выбран файл (picture[image]) — сохраняем его в
  # public/<folder>, читаем размеры/mime через MiniMagick и подставляем
  # получившиеся file/content_type/width/height в params для Picture.new/update.
  # Без выбранного файла просто пропускаем params как есть (правка метаданных
  # уже существующей картинки без переpivotа файла).
  #
  # max_bytes — необязательный потолок веса файла (для публичной загрузки,
  # где клиент должен был сжать фото сам, а сервер лишь подстраховывается;
  # админка вызывает без него — там ограничения по весу нет и не нужно).
  #
  # Возвращает [params, error_message] — error_message нужен только на неудаче.
  def process_picture_upload(picture_params, max_bytes: nil)
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
      raise "file too large (#{File.size(disk_path)} bytes, max #{max_bytes})" if max_bytes && File.size(disk_path) > max_bytes

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
