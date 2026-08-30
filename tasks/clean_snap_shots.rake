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
end
