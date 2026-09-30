# Локальная копия geonames.org (db/geonames.db, отдельное подключение —
# см. GeonamesRecord в app.rb). id тут — настоящий geonames.org id, тот
# самый, что теперь лежит в pages.geonames_id / tags.geonames_id.
#
# Отдельная БД — belongs_to/has_many ниже работают (Rails делает по ним
# обычные select по id, а не JOIN), но .joins(:geoname) и подобное — нет,
# разные подключения физически не смешать в одном SQL-запросе.
class Geoname < GeonamesRecord
  self.table_name = "geonames"

  def self.ransackable_attributes(auth_object = nil)
    %w[id name short slug feature_code country_code admin1_code admin2_code population]
  end
end
