# Разовая чистка мусора из geo:locality_from_address: артефакты вида
# "A Morro Bay"/"RR Grand Rapids"/"Clock Shop Columbia" — обрывки
# улиц/бизнес-названий, прилипшие к реальному городу при парсинге
# адреса. Список найден вручную (суффикс совпадает с уже существующим
# чистым тегом), "Mount Vernon"/"Key Largo" в него намеренно не
# включены — это настоящие составные топонимы, а не артефакты.
namespace :tags do
  desc "Слить artifact-теги addressLocality в их чистые пары (rake tags:cleanup_locality_dupes [dry_run=true])"
  task :cleanup_locality_dupes do
    dry_run = ENV['dry_run'] == 'true'

    pairs = [
      [2742, 2765], [2747, 2745], [2748, 2909], [2766, 2874], [2775, 2871],
      [2780, 2872], [2789, 2915], [2790, 2799], [2795, 2765], [2802, 2765],
      [2817, 2794], [2821, 2745], [2822, 2947], [2828, 2865], [2834, 2738],
      [2835, 2833], [2854, 3040], [2856, 2522], [2893, 2874], [2901, 2926],
      [2902, 2751], [2905, 2743], [2911, 2903], [2919, 2751], [2931, 2873],
      [2933, 2870], [2934, 3019], [2948, 2623], [2970, 2890], [2976, 2805],
      [2978, 2784], [2994, 2996], [3003, 2756], [3009, 2759], [3012, 2937],
      [3023, 2819], [3028, 2799], [3030, 2765], [3036, 2956], [3037, 2522],
      [3038, 2986]
    ]

    merged = []
    skipped = []

    ActiveRecord::Base.transaction do
      pairs.each do |source_id, target_id|
        source = Tag.find_by(id: source_id)
        target = Tag.find_by(id: target_id)

        unless source && target
          skipped << "##{source_id} -> ##{target_id}: не найден #{source ? 'target' : 'source'}"
          next
        end

        if source.fixed?
          skipped << "#{source.name}: fixed, не трогаем"
          next
        end

        if source.children.any?
          skipped << "#{source.name}: есть дети, не трогаем"
          next
        end

        source_taggings = source.taggings.count

        source.taggings.find_each do |tagging|
          if Tagging.exists?(tag_id: target.id, taggable_type: tagging.taggable_type, taggable_id: tagging.taggable_id)
            tagging.destroy
          else
            tagging.update!(tag_id: target.id)
          end
        end

        source.markers.update_all(tag_id: target.id) if source.respond_to?(:markers)

        source.schema_tags.find_each do |schema_tag|
          if SchemaTag.exists?(tag_id: target.id, schema_id: schema_tag.schema_id)
            schema_tag.destroy
          else
            schema_tag.update!(tag_id: target.id)
          end
        end

        name = source.name
        source.destroy!
        merged << "#{name} (##{source_id}, #{source_taggings} tagging) -> #{target.name} (##{target_id})"
      end

      puts "Слито: #{merged.size}"
      puts merged.join("\n")
      if skipped.any?
        puts "--- пропущено ---"
        puts skipped.join("\n")
      end

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Tag.count теперь #{Tag.count}"
  end
end
