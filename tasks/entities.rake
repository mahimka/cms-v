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

  DAYS_OF_WEEK = %w[monday tuesday wednesday thursday friday saturday sunday].freeze

  desc "Записать часы работы (hours_monday..hours_sunday из profile.details) в Detail Entity, группа Label opening_hours (rake entities:sync_opening_hours)"
  task :sync_opening_hours do
    opening_hours = Label.find_or_create_by!(name: 'opening_hours')

    day_labels = DAYS_OF_WEEK.each_with_object({}) do |day, h|
      key = "hours_#{day}"
      h[key] = Label.find_or_create_by!(name: key) { |l| l.parent_id = opening_hours.id }
    end

    total_details = 0
    entities_touched = 0

    Entity.find_each do |entity|
      hours_by_key = entity.profiles.each_with_object({}) do |profile, acc|
        details = profile.details || {}

        day_labels.each_key do |key|
          value = details[key]
          acc[key] ||= value if value.present?
        end
      end

      next if hours_by_key.empty?

      added = hours_by_key.count do |key, value|
        detail = Detail.find_or_initialize_by(detailable: entity, label: day_labels[key])
        next false if detail.persisted? && detail.value == value

        detail.value = value
        detail.save!
        true
      end

      next if added.zero?

      entities_touched += 1
      total_details += added
      puts "#{entity.name} (##{entity.id}): +#{added} detail(s)"
    end

    puts "Готово: #{entities_touched} entity, всего добавлено/обновлено #{total_details} деталей"
  end
end
