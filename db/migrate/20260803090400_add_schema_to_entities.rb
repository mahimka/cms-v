class AddSchemaToEntities < ActiveRecord::Migration[6.1]
  def up
    add_reference :entities, :schema, foreign_key: true

    # entity_type был свободной строкой — превращаем каждое уникальное
    # значение в узел Schema (без родителя, админ потом сам достроит
    # иерархию Schema.org и слаг) и переносим entities на schema_id.
    execute <<~SQL
      INSERT INTO schemas (name, slug, active, created_at, updated_at)
      SELECT DISTINCT entity_type, entity_type, 1, datetime('now'), datetime('now')
      FROM entities
      WHERE entity_type IS NOT NULL
        AND entity_type NOT IN (SELECT name FROM schemas)
    SQL

    execute <<~SQL
      UPDATE entities
      SET schema_id = (SELECT id FROM schemas WHERE schemas.name = entities.entity_type)
      WHERE entity_type IS NOT NULL
    SQL

    remove_column :entities, :entity_type, :string
  end

  def down
    add_column :entities, :entity_type, :string

    execute <<~SQL
      UPDATE entities
      SET entity_type = (SELECT name FROM schemas WHERE schemas.id = entities.schema_id)
      WHERE schema_id IS NOT NULL
    SQL

    remove_reference :entities, :schema, foreign_key: true
  end
end
