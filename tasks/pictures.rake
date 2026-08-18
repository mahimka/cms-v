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
end
