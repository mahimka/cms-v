# Цель — одинаковый slug у стран/регионов/городов на всех проектах на
# этом кодовом стеке, чтобы можно было взаимно ссылаться между сайтами
# по предсказуемому URL. db/geonames.db — общий для всех таких проектов
# справочник (копируется как есть), его slug и берём как канонический —
# даже если он длиннее/на другом языке, чем то, что тег носил раньше.
namespace :tags do
  desc "Синхронизировать Tag#slug с Geoname#slug (db/geonames.db) у всех тегов с geonames_id (rake tags:sync_geoname_slug [dry_run=true])"
  task :sync_geoname_slug do
    dry_run = ENV['dry_run'] == 'true'

    updated = []
    unchanged = 0
    collisions = []

    ActiveRecord::Base.transaction do
      Tag.where.not(geonames_id: nil).find_each do |tag|
        geoname = tag.geoname
        unless geoname&.slug.present?
          collisions << "##{tag.id} #{tag.name}: geoname #{tag.geonames_id} не найден или без slug"
          next
        end

        if tag.slug == geoname.slug
          unchanged += 1
          next
        end

        if Tag.where.not(id: tag.id).exists?(slug: geoname.slug)
          collisions << "##{tag.id} #{tag.name}: slug #{geoname.slug.inspect} уже занят другим тегом"
          next
        end

        old_slug = tag.slug
        tag.update_column(:slug, geoname.slug)
        updated << "#{tag.name}: #{old_slug.inspect} -> #{geoname.slug.inspect}"
      end

      puts "Обновлено: #{updated.size}, без изменений (уже совпадал): #{unchanged}, пропущено: #{collisions.size}"
      updated.first(20).each { |u| puts "  #{u}" }
      puts "  ... и ещё #{updated.size - 20}" if updated.size > 20
      if collisions.any?
        puts "--- пропущено ---"
        collisions.each { |c| puts "  #{c}" }
      end

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end
end
