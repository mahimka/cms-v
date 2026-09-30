# Тот же паттерн внешнего подключения, что в tasks/tags.rake (класс и
# помощник переопределяются здесь же на случай, если порядок загрузки
# .rake-файлов Rake'ом не гарантирует tags.rake раньше этого файла).
class ExternalDbConnection < ActiveRecord::Base
  self.abstract_class = true
end

class SourceLabel < ExternalDbConnection
  self.table_name = 'labels'
end

def connect_external_db!(path)
  raise "Укажи путь к чужой БД: db_path=/path/to/other/project/db/main.db" if path.blank?
  raise "Файл не найден: #{path}" unless File.exist?(path)

  ExternalDbConnection.establish_connection(adapter: 'sqlite3', database: path)
end

namespace :labels do
  desc "Скопировать дерево Label (detail_keys) из БД другого проекта на этом же коде, без дублей по имени (rake labels:import_from db_path=../kitezilla.com/db/main.db [dry_run=true])"
  task :import_from do
    connect_external_db!(ENV['db_path'])
    dry_run = ENV['dry_run'] == 'true'

    source = SourceLabel.all.map do |l|
      {
        'id' => l.id,
        'ancestry' => l.ancestry,
        'name' => l.name,
        'field_type' => l.field_type,
        'position' => l.position,
        'active' => l.active,
        'icon_svg' => l.icon_svg
      }
    end

    # has_ancestry хранит путь как "/1/5/" (id родителей от корня) — сортируем
    # по глубине пути, чтобы родитель всегда создавался/находился раньше ребёнка.
    source.sort_by! { |l| l['ancestry'].to_s.count('/') }

    id_map = {}
    created = []
    reused = 0

    ActiveRecord::Base.transaction do
      source.each do |l|
        existing = Label.find_by(name: l['name'])
        if existing
          id_map[l['id']] = existing.id
          reused += 1
          next
        end

        parent_source_id = l['ancestry'].to_s.split('/').compact_blank.last&.to_i
        parent_id = parent_source_id ? id_map[parent_source_id] : nil

        label = Label.create!(
          name: l['name'],
          field_type: l['field_type'],
          position: l['position'],
          active: l['active'].nil? ? true : l['active'],
          icon_svg: l['icon_svg']
        )
        label.update!(parent_id: parent_id) if parent_id

        id_map[l['id']] = label.id
        created << l['name']
      end

      puts "Найдено в источнике: #{source.size}, уже было (переиспользовано по имени): #{reused}, создано новых: #{created.size}"
      puts created.join(', ') if created.any?

      raise ActiveRecord::Rollback if dry_run
    end

    puts dry_run ? "DRY RUN — откачено, ничего не сохранено" : "Готово. Label.count теперь #{Label.count}"
  end
end
