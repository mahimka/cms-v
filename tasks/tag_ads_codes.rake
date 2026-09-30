namespace :tags do
  desc "Скопировать в Tag#short_2 код 'своего' уровня привязанного ads (Ad#own_level_code — country_code у страны, admin1_code у ADM1, admin2_code у ADM2; у населённых пунктов кода нет) (rake tags:copy_ads_codes [dry_run=true])"
  task :copy_ads_codes do
    dry_run = ENV['dry_run'] == 'true'

    updated = []
    skipped_no_code = []
    skipped_no_ad = []

    ActiveRecord::Base.transaction do
      Tag.where(table: 'ads').find_each do |tag|
        ad = tag.ad
        unless ad
          skipped_no_ad << tag.name
          next
        end

        code = ad.own_level_code
        if code.blank?
          skipped_no_code << "#{tag.name} (#{ad.feature_code})"
          next
        end

        # update_column, не update! — short_2 в GEONAMES_SYNCED_FIELDS,
        # Tag#protected_fields_unchanged_if_from_ads запрещает его менять
        # руками именно для того, чтобы данные шли только этим путём.
        tag.update_column(:short_2, code)
        updated << "#{tag.name} -> #{code}"
      end

      puts "Обновлено: #{updated.size}, без применимого кода (feature_code #{Ad::COUNTRY_FEATURE_CODES.join('/')}/ADM1/ADM2 не подошёл): #{skipped_no_code.size}, без ad: #{skipped_no_ad.size}"
      puts updated.join("\n") if updated.any?
      puts "--- без кода ---\n" + skipped_no_code.join("\n") if skipped_no_code.any?
      puts "--- без ad (битый table_id) ---\n" + skipped_no_ad.join("\n") if skipped_no_ad.any?

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  desc "Скопировать в Tag#slug slug привязанного ads (тоже в GEONAMES_SYNCED_FIELDS — geo:tag_from_ads исторически создавал теги без slug) (rake tags:copy_ads_slugs [dry_run=true])"
  task :copy_ads_slugs do
    dry_run = ENV['dry_run'] == 'true'

    updated = []
    renamed = []
    skipped_no_ad = []
    skipped_no_slug = []

    ActiveRecord::Base.transaction do
      Tag.where(table: 'ads').where(slug: [nil, '']).find_each do |tag|
        ad = tag.ad
        unless ad
          skipped_no_ad << tag.name
          next
        end

        if ad.slug.blank?
          skipped_no_slug << tag.name
          next
        end

        slug = ad.slug
        # Tag#slug уникален по ВСЕЙ таблице (гео + topical вместе), а не
        # только внутри ads, как Ad#slug — при редкой коллизии с чужим
        # тегом добавляем id.
        slug = "#{ad.slug}-#{tag.id}" if Tag.where.not(id: tag.id).exists?(slug: slug)
        renamed << "#{tag.name}: #{ad.slug} -> #{slug}" if slug != ad.slug

        tag.update_column(:slug, slug)
        updated << "#{tag.name} -> #{slug}"
      end

      puts "Обновлено: #{updated.size}, без ad: #{skipped_no_ad.size}, у ad пустой slug: #{skipped_no_slug.size}"
      puts "--- дизамбигуировано ---\n" + renamed.join("\n") if renamed.any?

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end
end
