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
end
