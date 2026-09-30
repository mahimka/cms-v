class LostUrl < ActiveRecord::Base

  validates :path, presence: true, uniqueness: true

  scope :unreviewed, -> { where(reviewed: false) }

  def self.ransackable_attributes(auth_object = nil)
    %w[path referrer ip hits_count first_seen_at last_seen_at reviewed created_at updated_at]
  end

  # Разбирает lib/lost_url_logger.rb-лог (path\treferrer\tip\tdatetime за
  # строку — см. LostUrlLogger.record) и upsert'ит в lost_urls по path:
  # новый path -> создаём с hits_count=1, уже знакомый -> прибавляем
  # hits_count и подвигаем last_seen_at/referrer/ip на самые свежие.
  # После успешного разбора лог-файл очищается (не удаляется — под ним
  # уже могут писать), чтобы не заимпортить те же строки повторно.
  def self.import_from_log!
    path = LostUrlLogger::LOG_PATH
    return { imported: 0, rows: 0 } unless File.exist?(path)

    lines = File.readlines(path, chomp: true).reject(&:blank?)
    return { imported: 0, rows: 0 } if lines.empty?

    grouped = lines.each_with_object({}) do |line, memo|
      time_s, req_path, referrer, ip = line.split("\t")
      next if req_path.blank?

      time = Time.iso8601(time_s) rescue Time.now.utc

      entry = memo[req_path] ||= { count: 0, first: time, last: time, referrer: referrer, ip: ip }
      entry[:count] += 1
      entry[:first] = time if time < entry[:first]
      if time >= entry[:last]
        entry[:last] = time
        entry[:referrer] = referrer
        entry[:ip] = ip
      end
    end

    ActiveRecord::Base.transaction do
      grouped.each do |req_path, entry|
        record = LostUrl.find_or_initialize_by(path: req_path)
        record.hits_count = (record.persisted? ? record.hits_count : 0) + entry[:count]
        record.first_seen_at ||= entry[:first]
        record.last_seen_at = entry[:last] if record.last_seen_at.nil? || entry[:last] >= record.last_seen_at
        record.referrer = entry[:referrer] if entry[:referrer].present?
        record.ip = entry[:ip] if entry[:ip].present?
        record.save!
      end
    end

    # Файл, а не File.delete — под ним может дописывать другой процесс
    # прямо сейчас, усечение безопаснее удаления.
    File.truncate(path, 0)

    { imported: grouped.size, rows: lines.size }
  end
end
