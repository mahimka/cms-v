module SchemaIdentifiable
  extend ActiveSupport::Concern

  # Стабильный уникальный идентификатор объекта для schema.org @id,
  # например "entity-42". Называется не schema_id — у Entity/Item/Event
  # уже есть настоящая колонка schema_id (FK на Schema, belongs_to :schema),
  # метод с тем же именем её бы просто перекрыл.
  # page.pageable.ld_id — не page.source_page.pageable, pageable уже сам
  # резолвит правильный объект и для переводов.
  def ld_id
    "#{self.class.name.downcase}-#{id}"
  end
end
