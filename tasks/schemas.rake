namespace :schemas do
  desc "Создать схему LocalBusiness, если её ещё нет (rake schemas:seed_local_business)"
  task :seed_local_business do
    schema = Schema.find_or_create_by!(name: "LocalBusiness") do |s|
      s.schema_org_url = "https://schema.org/LocalBusiness"
      s.active = true
    end

    puts "Schema ##{schema.id} #{schema.name} (#{schema.schema_org_url})"
  end

  desc "Привязать корневые группы тегов и лейблов к схеме LocalBusiness через schema_tags/schema_labels (rake schemas:bind_tag_groups [dry_run=true])"
  task :bind_tag_groups do
    dry_run = ENV['dry_run'] == 'true'

    schema = Schema.find_by!(name: "LocalBusiness")

    # "art of living" оказался на верхнем уровне не как группа, а из-за
    # битой ссылки parent_id (732) на несуществующую запись в источнике
    # old_yogamela — единственное исключение, остальные корневые тегсеты
    # привязываем все, включая пустые Unsorted/dirty (так решил пользователь).
    tag_group_names = Tag.where(parent_id: nil).where.not(name: 'art of living').pluck(:name)
    label_group_names = %w[contact_labels link_labels]

    added_tags = []
    added_labels = []

    ActiveRecord::Base.transaction do
      tag_group_names.each do |name|
        tag = Tag.find_by!(name: name)
        next if SchemaTag.exists?(schema_id: schema.id, tag_id: tag.id)

        SchemaTag.create!(schema_id: schema.id, tag_id: tag.id)
        added_tags << name
      end

      label_group_names.each do |name|
        label = Label.find_by!(name: name)
        next if SchemaLabel.exists?(schema_id: schema.id, label_id: label.id)

        SchemaLabel.create!(schema_id: schema.id, label_id: label.id)
        added_labels << name
      end

      puts "Привязано групп тегов: #{added_tags.size} (#{added_tags.join(', ')})"
      puts "Привязано групп лейблов: #{added_labels.size} (#{added_labels.join(', ')})"

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  desc "Удалить схемы с active: false, на которые ничего не ссылается (entities/items/events/page_templates, нет детей, которые остаются). schema_tags/schema_labels уходят вместе со схемой (rake schemas:delete_unused [dry_run=true])"
  task :delete_unused do
    dry_run = ENV['dry_run'] == 'true'

    used_by = lambda do |schema|
      refs = { 'entities' => Entity, 'items' => Item, 'events' => Event, 'page_templates' => PageTemplate }
      refs.filter_map { |label, model| (n = model.where(schema_id: schema.id).count) > 0 ? "#{label}: #{n}" : nil }
    end

    candidates = Schema.where(active: false).to_a.select { |s| used_by.call(s).empty? }
    kept = Schema.where(active: false).to_a - candidates

    # схема с потомками, которые останутся (активные или используемые), остаётся сама —
    # иначе ancestry удалил бы потомков вместе с ней
    loop do
      ids = candidates.map(&:id)
      blocked = candidates.select { |s| s.descendants.any? { |d| !ids.include?(d.id) } }
      break if blocked.empty?

      candidates -= blocked
      kept += blocked
    end

    puts "Неактивных схем: #{candidates.size + kept.size}, к удалению: #{candidates.size}, остаётся: #{kept.size}"
    kept.each do |s|
      reasons = used_by.call(s)
      reasons << 'есть потомки, которые остаются' if reasons.empty?
      puts "  оставлена ##{s.id} #{s.name.strip}: #{reasons.join(', ')}"
    end

    ActiveRecord::Base.transaction do
      # сначала самые глубокие, чтобы удаление не зависело от orphan_strategy ancestry
      candidates.sort_by { |s| -s.depth }.each do |schema|
        tags   = schema.schema_tags.count
        labels = schema.schema_labels.count
        puts "  удалить ##{schema.id} #{schema.name.strip}#{" (schema_tags: #{tags}, schema_labels: #{labels})" if tags + labels > 0}"
        schema.destroy! if Schema.exists?(schema.id)
      end

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не удалено" : "Готово. Схем осталось: #{Schema.count}"
  end
end
