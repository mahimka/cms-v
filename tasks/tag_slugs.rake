namespace :tags do
  desc "Заполнить Tag#slug из name (SlugGenerator); уже проставленные slug не трогает, при занятости добавляет -1, -2, ... (rake tags:generate_slugs [dry_run=true])"
  task :generate_slugs do
    dry_run = ENV['dry_run'] == 'true'

    updated = []
    skipped = 0

    ActiveRecord::Base.transaction do
      Tag.find_each do |tag|
        if tag.slug.present?
          skipped += 1
          next
        end

        base_slug = SlugGenerator.call(tag.name)
        slug = base_slug
        n = 0
        while Tag.where(slug: slug).where.not(id: tag.id).exists?
          n += 1
          slug = "#{base_slug}-#{n}"
        end

        tag.update!(slug: slug)
        updated << "#{tag.name} -> #{slug}"
      end

      puts "Обновлено: #{updated.size}, пропущено (slug уже был): #{skipped}"
      puts updated.join("\n") if updated.any?

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Tag.where(slug: nil).count теперь #{Tag.where(slug: nil).count}"
  end
end
