require 'sqlite3'

# Лёгкие модели на ОТДЕЛЬНОМ подключении к чужой SQLite-базе того же
# приложения (например ../cms-diversorio/db/main.db) — не трогают
# основное ActiveRecord::Base.connection, поэтому текущий проект спокойно
# продолжает читать/писать свою БД, пока мы читаем чужую.
class ExternalDbConnection < ActiveRecord::Base
  self.abstract_class = true
end

class SourceTag < ExternalDbConnection
  self.table_name = 'tags'
end

class SourceMarker < ExternalDbConnection
  self.table_name = 'markers'
  belongs_to :tag, class_name: 'SourceTag', optional: true
end

def connect_external_db!(path)
  raise "Укажи путь к чужой БД: db_path=/path/to/other/project/db/main.db" if path.blank?
  raise "Файл не найден: #{path}" unless File.exist?(path)

  ExternalDbConnection.establish_connection(adapter: 'sqlite3', database: path)
end

namespace :tags do
  desc "Скопировать теги (иерархию Tag) из БД другого проекта на этом же коде, без дублей по имени (rake tags:import_from db_path=../cms-diversorio/db/main.db [dry_run=true])"
  task :import_from do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    source = SourceTag.all.map do |t|
      {
        'id' => t.id,
        'name' => t.name,
        'parent_id' => t.parent_id,
        'position' => t.position,
        'short' => t.short,
        'short_2' => t.short_2,
        'active' => t.active,
        'icon_svg' => t.icon_svg
      }
    end
    roots, children = source.partition { |t| t['parent_id'].nil? }

    id_map = {}
    created = []
    reused = 0

    resolve = lambda do |t|
      existing = Tag.find_by(name: t['name'])
      if existing
        id_map[t['id']] = existing.id
        reused += 1
      else
        parent_id = t['parent_id'] ? id_map[t['parent_id']] : nil
        tag = Tag.create!(
          name: t['name'],
          parent_id: parent_id,
          position: t['position'],
          short: t['short'],
          short_2: t['short_2'],
          active: t['active'].nil? ? true : t['active'],
          icon_svg: t['icon_svg']
        )
        id_map[t['id']] = tag.id
        created << t['name']
      end
    end

    ActiveRecord::Base.transaction do
      roots.each { |t| resolve.call(t) }
      children.each { |t| resolve.call(t) }

      puts "Найдено в источнике: #{source.size}, уже было (переиспользовано по имени): #{reused}, создано новых: #{created.size}"
      puts created.join(', ') if created.any?

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Tag.count теперь #{Tag.count}"
  end

  desc "Проставить Marker.tag_id: сперва по карте соответствий group+name->tag.name уже размеченных маркеров другого проекта, потом по точному совпадению имени (rake tags:link_markers db_path=../cms-diversorio/db/main.db [site=tripadvisor.com] [dry_run=true])"
  task :link_markers do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: ENV['site'] || 'tripadvisor.com')

    ref_map = {}
    SourceMarker.where.not(tag_id: nil).includes(:tag).find_each do |m|
      next unless m.tag

      key = [m.group, m.name.to_s.strip.downcase]
      ref_map[key] ||= m.tag.name
    end
    puts "Карта соответствий из источника: #{ref_map.size} пар group+name -> tag.name"

    markers = Marker.where(site_id: site.id, tag_id: nil)
    puts "Маркеров без tag_id: #{markers.count}"

    via_reference = 0
    via_direct = 0
    unmatched = []

    ActiveRecord::Base.transaction do
      markers.find_each do |m|
        key = [m.group, m.name.to_s.strip.downcase]
        tag_name = ref_map[key]
        tag = tag_name && Tag.find_by(name: tag_name)

        if tag
          via_reference += 1
        else
          tag = Tag.find_by(name: m.name) || Tag.where('LOWER(name) = ?', m.name.to_s.strip.downcase).first
          via_direct += 1 if tag
        end

        if tag
          m.update!(tag_id: tag.id)
        else
          unmatched << "#{m.group} / #{m.name}"
        end
      end

      puts "via_reference=#{via_reference} via_direct=#{via_direct} unmatched=#{unmatched.size}"

      raise ActiveRecord::Rollback if dry_run
    end

    if unmatched.any?
      puts "--- unmatched (по группам) ---"
      unmatched.group_by { |u| u.split(' / ').first }.each { |g, list| puts "#{g}: #{list.size}" }
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово"
  end

  desc "Для маркеров сайта, у которых так и не нашёлся tag_id, создать группу ta_<группа маркера> и тег с именем маркера; при занятом имени добавляет _ta (rake tags:create_missing db_path=... [site=tripadvisor.com] [dry_run=true])"
  task :create_missing do
    dry_run = ENV['dry_run'] == 'true'
    site = Site.find_by!(domain: ENV['site'] || 'tripadvisor.com')

    markers = Marker.where(site_id: site.id, tag_id: nil).order(:group, :name)
    puts "Маркеров без tag_id: #{markers.count}"

    unique_tag_name = lambda do |base_name|
      name = base_name
      name = "#{base_name}_ta" while Tag.exists?(name: name)
      name
    end

    created_groups = []
    created_tags = 0
    linked = 0

    ActiveRecord::Base.transaction do
      markers.group_by(&:group).each do |group_name, group_markers|
        group_tag_name = "ta_#{group_name}"
        group_tag = Tag.find_by(name: group_tag_name)
        if group_tag.nil?
          group_tag = Tag.create!(name: group_tag_name, parent_id: nil, active: true)
          created_groups << group_tag_name
        end

        group_markers.each do |m|
          tag = Tag.find_by(name: m.name)
          if tag.nil?
            final_name = unique_tag_name.call(m.name)
            tag = Tag.create!(name: final_name, parent_id: group_tag.id, active: true)
            created_tags += 1
          end
          m.update!(tag_id: tag.id)
          linked += 1
        end
      end

      puts "Новых групп: #{created_groups.size} (#{created_groups.join(', ')})"
      puts "Новых тегов: #{created_tags}, привязано маркеров: #{linked}"

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Tag.count теперь #{Tag.count}"
  end
end
