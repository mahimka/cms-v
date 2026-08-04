require './environment'
require 'sinatra/activerecord/rake'


task :stats do
  puts "Profiles Brands " + Profile.where(profileable_type: "Brand").count.to_s
  puts "Profiles Item " + Profile.where(profileable_type: "Item").count.to_s

  Profile.where(profileable_type: "Item").first(10).each do |profile|
    puts profile.inspect
  end
end

task :create_site do 
    puts "herer"
    site = Site.find_or_create_by(domain: 'parfumo.com')
    site.name = "Parfumo"
    site.url = "https://www.parfumo.com/"
    site.save
    puts site.name


    # t.string "name"
    # t.string "url"
    # t.string "domain"
    # t.datetime "created_at", precision: 6, null: false
    # t.datetime "updated_at", precision: 6, null: false

end


namespace :items do
  desc "Полностью очищает таблицу items и сбрасывает AUTOINCREMENT"
  # task truncate: :environment do
  task :truncate do
    # 1. Удаляем все записи из таблицы
    ActiveRecord::Base.connection.execute("DELETE FROM items;")

    # 2. Обнуляем автоинкремент в системной таблице SQLite
    ActiveRecord::Base.connection.execute("DELETE FROM sqlite_sequence WHERE name = 'items';")

    # 3. (Опционально) Освобождаем неиспользуемое дисковое пространство
    ActiveRecord::Base.connection.execute("VACUUM;")

    puts "Таблица 'items' успешно очищена, ID сброшен на 1."
  end
end


namespace :taggings do
  desc "Удаляет записи taggable_type='Item' из taggings и обновляет autoincrement"
  # task cleanup_items: :environment do
  task :cleanup_items do
    connection = ActiveRecord::Base.connection

    # 1. Удаляем только записи с taggable_type = 'Item'
    deleted_count = Tagging.where(taggable_type: 'Item').delete_all
    puts "Удалено записей: #{deleted_count}"

    # 2. Находим максимальный ID среди оставшихся записей
    max_id = Tagging.maximum(:id) || 0

    # 3. Корректируем счетчик autoincrement в SQLite
    if max_id == 0
      # Если таблица стала пустой, полностью сбрасываем счетчик
      connection.execute("DELETE FROM sqlite_sequence WHERE name = 'taggings';")
    else
      # Если записи остались, выставляем autoincrement на максимальный существующий ID
      connection.execute("UPDATE sqlite_sequence SET seq = #{max_id} WHERE name = 'taggings';")
    end

    puts "Автоинкремент таблицы 'taggings' выставлен на: #{max_id} (следующий ID будет #{max_id + 1})"
  end
end