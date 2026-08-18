class Picture < ActiveRecord::Base
  include Taggable

  serialize :translations, JSON

  scope :active, -> { where(active: true) }
  scope :published, -> { where(published: true) }

  belongs_to :imageable, polymorphic: true
  belongs_to :user, optional: true

  validates :file, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["active", "id", "imageable_type", "imageable_id", "file", "alt", "content_type", "width", "height", "ratio", "published", "position", "user_id", "latitude", "longitude", "taken_at", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["imageable", "tags", "user"]
  end

  # Alt-текст на язык страницы. Переводится вручную в админке
  # (translations — hash locale => строка), при отсутствии — фолбэк на alt.
  def translation(lang)
    translations&.dig(lang.to_s).presence || alt
  end

  after_save :sync_exif_metadata, if: :sync_exif_metadata?

  # Пишет author/title/GPS/дату СЪЁМКИ из полей записи обратно в файл на диске
  # (exiftool через MiniExiftool, см. environment.rb) — чтобы при скачивании
  # файла эти данные были видны в его собственных метаданных, не только в
  # админке. Молча не делает ничего, если файла нет на диске; ошибки самого
  # exiftool не должны ронять сохранение записи, поэтому rescue.
  def sync_exif_metadata
    disk_path = File.join(PUBLIC_FOLDER, file.to_s)
    return unless File.exist?(disk_path)

    photo = MiniExiftool.new(disk_path)
    photo.image_description = alt if alt.present?
    photo.artist = user.name if user

    if latitude.present? && longitude.present?
      photo.gps_latitude = latitude.abs
      photo.gps_latitude_ref = latitude.negative? ? "S" : "N"
      photo.gps_longitude = longitude.abs
      photo.gps_longitude_ref = longitude.negative? ? "W" : "E"
    end

    photo.date_time_original = taken_at if taken_at

    photo.save
  rescue StandardError => e
    puts "Picture#sync_exif_metadata (id=#{id}) failed: #{e.message}"
  end

  private

  def sync_exif_metadata?
    file.present? && (saved_change_to_alt? || saved_change_to_user_id? || saved_change_to_latitude? ||
                       saved_change_to_longitude? || saved_change_to_taken_at? || saved_change_to_file?)
  end

end
