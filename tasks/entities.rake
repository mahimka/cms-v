namespace :entities do
  desc "Тегировать Entity тегами, привязанными к markers его profiles (rake entities:tag_from_markers)"
  task :tag_from_markers do
    total_taggings = 0
    entities_touched = 0

    Entity.find_each do |entity|
      tag_ids = entity.profiles
                       .joins(:markers)
                       .where.not(markers: { tag_id: nil })
                       .distinct
                       .pluck("markers.tag_id")

      next if tag_ids.empty?

      added = tag_ids.count do |tag_id|
        next false if entity.taggings.exists?(tag_id: tag_id)

        entity.taggings.create!(tag_id: tag_id)
        true
      end

      next if added.zero?

      entities_touched += 1
      total_taggings += added
      puts "#{entity.name} (##{entity.id}): +#{added} tag(s)"
    end

    puts "Готово: #{entities_touched} entity, всего добавлено #{total_taggings} привязок"
  end
end
