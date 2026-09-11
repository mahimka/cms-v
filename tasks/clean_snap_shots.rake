namespace :snap_shots do
  desc "Дочистить html_content у ещё не распарсенных SnapShot (убрать img + все атрибуты кроме href) (rake snap_shots:reclean)"
  task :reclean do
    scope = SnapShot.where(parsed: [false, nil])
    total = scope.count
    puts "Найдено #{total} неразобранных snap_shot(ов)"

    saved_chars = 0

    scope.find_each.with_index do |snap_shot, i|
      before = snap_shot.html_content.length

      doc = Nokogiri::HTML(snap_shot.html_content)
      doc.css('img').remove
      doc.css('*').each do |el|
        el.attributes.each_key { |name| el.remove_attribute(name) unless name == 'href' }
      end

      cleaned = doc.to_html
      after = cleaned.length
      saved_chars += (before - after)

      snap_shot.update_column(:html_content, cleaned)

      puts "##{snap_shot.id}: #{before} -> #{after} (-#{((before - after).to_f / before * 100).round(1)}%)" if (i + 1) % 25 == 0 || i == 0
    end

    puts "Готово: #{total} snap_shot(ов), суммарно сэкономлено #{saved_chars} символов"
  end

  desc "Затереть html_content у уже разобранных (parsed=true) SnapShot — вся нужная информация уже перенесена в profile.details/markers/tags, хранить сырой HTML дальше незачем (rake snap_shots:clear_parsed_html)"
  task :clear_parsed_html do
    scope = SnapShot.where(parsed: true).where.not(html_content: [nil, ''])
    total = scope.count
    puts "Найдено #{total} разобранных snap_shot(ов) с непустым html_content"

    freed_bytes = 0
    scope.find_each do |snap_shot|
      freed_bytes += snap_shot.html_content.to_s.bytesize
      snap_shot.update_column(:html_content, nil)
    end

    puts "Готово: очищено #{total} snap_shot(ов), освобождено ~#{(freed_bytes / 1024.0 / 1024).round(1)} MB данных"
    puts "Файл БД физически уменьшится только после VACUUM (rake snap_shots:vacuum_db или вручную)"
  end

  desc "VACUUM базы — физически сжимает файл main.db после удаления/затирания данных (rake snap_shots:vacuum_db)"
  task :vacuum_db do
    before = File.size(ActiveRecord::Base.connection_db_config.database)
    ActiveRecord::Base.connection.execute('VACUUM')
    after = File.size(ActiveRecord::Base.connection_db_config.database)
    puts "Файл БД: #{(before / 1024.0 / 1024).round(1)} MB -> #{(after / 1024.0 / 1024).round(1)} MB"
  end
end
