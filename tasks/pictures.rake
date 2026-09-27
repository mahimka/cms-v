namespace :pictures do
  desc "Пишет author/title/GPS/дату из полей Picture обратно в EXIF файлов на диске (задним числом — для картинок, загруженных до Picture#sync_exif_metadata)"
  task :exif_backfill do
    scope = Picture.where(
      "alt IS NOT NULL OR user_id IS NOT NULL OR latitude IS NOT NULL OR taken_at IS NOT NULL"
    )

    total = scope.count
    puts "Пишу EXIF в #{total} картинок..."

    ok = 0
    failed = []

    scope.find_each.with_index do |picture, i|
      disk_path = File.join(PUBLIC_FOLDER, picture.file.to_s)

      unless File.exist?(disk_path)
        failed << [picture.id, "файл не найден: #{disk_path}"]
        next
      end

      picture.sync_exif_metadata
      ok += 1
      print "." if (i + 1) % 20 == 0
    end

    puts
    puts "Готово: #{ok}/#{total}"

    if failed.any?
      puts "Не найден файл (#{failed.size}):"
      failed.each { |id, msg| puts "  ##{id} — #{msg}" }
    end
  end

  desc "Разовая чистка скриншотов сайтов: удаляет отклонённые (active: false) и лишние дубли (имя файла включает дату — повторный прогон в другой день плодил новую Picture вместо замены старой), оставляя максимум одну на entity (rake pictures:cleanup_website_screenshots [dry_run=true])"
  task :cleanup_website_screenshots do
    dry_run = ENV['dry_run'] == 'true'

    scope = Picture.where(imageable_type: 'Entity').where("file LIKE ?", "/images/screenshots/%")

    removed_inactive = 0
    removed_dupes = 0

    remove = lambda do |picture|
      puts "  ##{picture.id} #{picture.file} (active=#{picture.active})#{dry_run ? ' (dry_run)' : ''}"
      next if dry_run

      disk = File.join(PUBLIC_FOLDER, picture.file.to_s)
      File.delete(disk) if File.exist?(disk)
      picture.destroy!
    end

    puts "-- отклонённые (active: false) --"
    scope.where(active: false).find_each do |picture|
      remove.call(picture)
      removed_inactive += 1
    end

    puts "-- дубли (оставляем самую новую на entity) --"
    scope.where(active: true).group_by(&:imageable_id).each_value do |pictures|
      next if pictures.size <= 1

      pictures.sort_by(&:id).first(pictures.size - 1).each do |picture|
        remove.call(picture)
        removed_dupes += 1
      end
    end

    puts "Удалено отклонённых: #{removed_inactive}, удалено дублей: #{removed_dupes}"
  end
end
