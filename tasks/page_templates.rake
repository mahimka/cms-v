# Массовая генерация страниц по PageTemplate (PageTemplateGenerator) —
# и на первичный прогон, и на force-регенерацию — раньше гонялась через
# admin POST /page_templates/:id/generate (один template за раз, только
# из браузера) либо ad-hoc `bundle exec ruby -e`. Задачи ниже — то же
# самое, но воспроизводимо и с dry_run.
# Объекты, для которых страницу не удалось построить (ProfileUri: нет родителя
# или тега) — первые 15 причин.
def print_failed(failed)
  return if failed.blank?

  puts "  не создано #{failed.size}:"
  failed.first(15).each { |failure| puts "    - #{failure[:reason]}" }
  puts "    … и ещё #{failed.size - 15}" if failed.size > 15
end

namespace :page_templates do
  desc "Сгенерировать страницы по одному PageTemplate (rake page_templates:generate id=1 [force=true] [dry_run=true])"
  task :generate do
    id = ENV['id']
    raise "Укажи id=<page_template id> (rake page_templates:generate id=1)" if id.blank?

    force = ENV['force'] == 'true'
    dry_run = ENV['dry_run'] == 'true'
    page_template = PageTemplate.find(id)

    ActiveRecord::Base.transaction do
      result = PageTemplateGenerator.run(page_template, force: force)
      puts "##{page_template.id} (#{page_template.template_type}, #{page_template.slug.inspect}): " \
           "создано #{result[:created].size}, обновлено #{result[:updated].size}, пропущено #{result[:skipped].size}"
      print_failed(result[:failed])

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  # Родительские List-шаблоны должны сгенерироваться раньше вложенных —
  # nested List (parent_template_id) берёт СУЩЕСТВУЮЩИЕ Page родителя
  # (PageTemplateGenerator#list_targets: Page.where(template_id:
  # parent_template_id)), а не генерирует их на лету.
  desc "Сгенерировать страницы по всем активным PageTemplate, родители раньше вложенных (rake page_templates:generate_all [force=true] [ids=1,2,3] [dry_run=true])"
  task :generate_all do
    force = ENV['force'] == 'true'
    dry_run = ENV['dry_run'] == 'true'
    only_ids = ENV['ids']&.split(',')&.map(&:to_i)

    scope = PageTemplate.where(active: true)
    scope = scope.where(id: only_ids) if only_ids.present?

    depth_cache = {}
    depth = lambda do |page_template|
      depth_cache[page_template.id] ||=
        page_template.parent_template_id.present? ? depth.call(page_template.parent_template) + 1 : 0
    end

    ordered = scope.sort_by { |page_template| depth.call(page_template) }

    # Внимание: nested List под addressLocality (сотни-тысячи родительских
    # страниц) — известно медленные, N+1 в list_targets/group_tags
    # (список пар <родитель, теги> считается заново на каждую
    # родительскую страницу без кеша). Для них лучше id= один за раз,
    # не все сразу в общем прогоне.
    ActiveRecord::Base.transaction do
      ordered.each do |page_template|
        result = PageTemplateGenerator.run(page_template, force: force)
        puts "##{page_template.id} (#{page_template.template_type}, #{page_template.slug.inspect}): " \
             "создано #{result[:created].size}, обновлено #{result[:updated].size}, пропущено #{result[:skipped].size}"
      end

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  desc "Привязать уже созданные страницы (Profile и List) к PageTemplate, не затирая отличающиеся поля (rake page_templates:adopt id=1 [rebind=true] [dry_run=true])"
  task :adopt do
    id = ENV['id']
    raise "Укажи id=<page_template id> (rake page_templates:adopt id=1)" if id.blank?

    page_template = PageTemplate.find(id)
    dry_run = ENV['dry_run'] == 'true'

    result = nil
    ActiveRecord::Base.transaction do
      result = PageTemplateGenerator.new(page_template).adopt(rebind: ENV['rebind'] == 'true')
      raise ActiveRecord::Rollback if dry_run
    end

    result[:adopted].each do |page, differing|
      puts "#{page.uri}: template_id=#{page_template.id}, отличаются: #{differing.empty? ? '-' : differing.join(', ')}"
    end
    puts "##{page_template.id} (#{page_template.slug.inspect}): привязано #{result[:adopted].size}, " \
         "без изменений #{result[:unchanged].size}, пропущено (другой template) #{result[:skipped].size}"
    result[:mismatched].each { |m| puts "  ! родитель не совпадает, не привязана: #{m[:page].uri} (по шаблону родитель #{m[:expected]})" }
    print_failed(result[:failed])
    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end
end
