# Поддерживает hub/facet-страницы по локации для Entity, чья схема
# настроена в config.yml (page_cascades.<name>.trigger_schemas).
# Настройки полностью в config.yml — класс общий, ни одной схемы/группы
# не знает "зашито". НЕ запускается автоматически при сохранении/
# тегировании Entity — только вручную, см. PageCascade.run_all и кнопки
# на /admin/entities (по одной на каждый ключ page_cascades).
#
# hub-страница ("/egypt") — корневая, per location_level (группа
# addressCountry/addressRegion/adm_2/addressLocality), по тегу entity
# из этой группы. facet-страница ("/egypt/kite-rental") — ребёнок
# hub-страницы, по каждому тегу entity из facet-группы этого уровня
# (facets[level]). Создаются только под теги, которыми entity реально
# помечена — полный декартов набор locations x facet-тегов дал бы
# тысячи пустых страниц.
class PageCascade
  def self.all_configs
    App.settings.page_cascades || {}
  end

  def self.config(name)
    all_configs[name.to_s] || {}
  end

  def self.enabled_for?(entity, name)
    cfg = config(name)
    schema_name = entity.schema&.name
    return false if schema_name.blank?
    return false unless cfg["trigger_schemas"].to_a.include?(schema_name)

    # ListQuery (двигатель list-страниц) показывает только объекты с
    # published-страницей — hub/facet-страница, созданная раньше, была
    # бы пустой до публикации entity.
    entity.page&.published? || false
  end

  # Активные Entity, для которых этот каскад в принципе применим
  # (schema.name в trigger_schemas, есть published detail-страница) —
  # то, что должна перебрать кнопка "create lists" на /admin/entities.
  def self.eligible_entities(name)
    cfg = config(name)
    schema_names = cfg["trigger_schemas"].to_a
    return Entity.none if schema_names.empty?

    published_ids = Page.where(pageable_type: "Entity", published: true).select(:pageable_id)

    Entity.active.joins(:schema).where(schemas: { name: schema_names }).where(id: published_ids)
  end

  # Прогоняет каскад по всем eligible_entities разом — то, что делает
  # кнопка "create lists". force: false (по умолчанию) — только создаёт
  # недостающие страницы, уже существующие не трогает (страницы часто
  # правятся руками — обычный прогон не должен затирать эти правки).
  # force: true — ещё и обновляет все поля существующих страниц по
  # текущему config.yml (отдельная кнопка "force refresh").
  # Возвращает {entities:, pages_created:, pages_updated:} для флеша.
  def self.run_all(name, force: false)
    entities = eligible_entities(name).to_a
    created = 0
    updated = 0

    entities.each do |entity|
      result = new(entity, name).run(force: force)
      created += result[:created].size
      updated += result[:updated].size
    end

    { entities: entities.size, pages_created: created, pages_updated: updated }
  end

  def initialize(entity, cascade_name)
    @entity = entity
    @cascade_name = cascade_name.to_s
    @config = self.class.config(cascade_name)
  end

  # force: false (по умолчанию) — find-or-CREATE: страницы, которых не
  # было, создаёт; уже существующие пропускает как есть (не затирает
  # ручные правки). force: true — find-or-UPDATE: существующие тоже
  # обновляет всеми полями (title/h1/subtitle/anchor_1-3/view/layout/
  # conditions) по текущему config.yml.
  # Возвращает {created: [...], updated: [...]}.
  def run(force: false)
    return { created: [], updated: [] } unless self.class.enabled_for?(@entity, @cascade_name)

    created = []
    updated = []

    # Теги entity по всем уровням сразу (не по одному в цикле) — чтобы
    # в шаблоне hub/facet-страницы уровня addressRegion можно было
    # сослаться и на %{addressCountry.short} entity, а не только на
    # тег текущего уровня.
    tags_by_level = location_levels.each_with_object({}) do |level, hash|
      tag = tag_in_group(level)
      hash[level] = tag if tag
    end

    tags_by_level.each do |level, location_tag|
      hub_page, hub_status = ensure_hub_page(level, location_tag, tags_by_level, force)
      created << hub_page if hub_status == :created
      updated << hub_page if hub_status == :updated

      facet_groups_for(level).each do |facet_group|
        facet_tags_in_group(facet_group).each do |facet_tag|
          facet_page, facet_status = ensure_facet_page(level, hub_page, facet_tag, location_tag, tags_by_level, force)
          created << facet_page if facet_status == :created
          updated << facet_page if facet_status == :updated
        end
      end
    end

    { created: created, updated: updated }
  end

  private

  def location_levels
    @config["location_levels"].to_a
  end

  def facet_groups_for(level)
    (@config["facets"] || {})[level].to_a
  end

  def trigger_schemas
    @config["trigger_schemas"].to_a
  end

  # view/layout настраиваются НА КАЖДЫЙ location_level отдельно — ключи
  # "view"/"layout" внутри hub_fields[level]/facet_fields[level], рядом
  # с title/h1/... (см. config.yml). Если для уровня не заданы —
  # берём верхнеуровневые view/layout каскада, если и их нет —
  # "default.erb".
  #
  # ВАЖНО: значение — это имя файла КАК ЕСТЬ, с расширением ".erb"
  # ("country.erb", не "country") — MiscHelpers#call_erb_view ищет файл
  # через File.file?(File.join(views, view)) буквально по этой строке;
  # без расширения файл не находится и метод молча откатывается на
  # app/views/default.erb (а он НЕ выводит @objects — список
  # entities/страница выглядит пустой, без явной ошибки).
  def view_for(templates_key, level)
    level_view = ((@config[templates_key] || {})[level] || {})["view"]
    level_view.presence || @config["view"].presence || "default.erb"
  end

  def layout_for(templates_key, level)
    level_layout = ((@config[templates_key] || {})[level] || {})["layout"]
    level_layout.presence || @config["layout"].presence || "default.erb"
  end

  def home_language
    App.settings.home_language
  end

  # Page#calculated_uri отдаёт "/" для ЛЮБОЙ страницы без родителя
  # (parent.nil? — не про slug), поэтому "верхний уровень" вроде /egypt
  # на самом деле ребёнок корневой страницы ("/"), а не сам root —
  # ровно как обычные /products и т.п. в этом проекте.
  def root_page
    @root_page ||= Page.masters.roots.find_by!(lang: home_language)
  end

  # Тег entity, принадлежащий указанной группе (её parent.name == group).
  # active: true и fixed: true — тег ещё не "устоялся" (могут
  # переименовать/удалить), по нему страницу не создаём.
  def tag_in_group(group_name)
    @entity.tags.joins(:parent).where(active: true, fixed: true).find_by(parent: { name: group_name })
  end

  # Все теги entity, принадлежащие указанной facet-группе (тот же
  # active/fixed гейт).
  def facet_tags_in_group(group_name)
    @entity.tags.joins(:parent).where(active: true, fixed: true).where(parent: { name: group_name })
  end

  # Короткое отображаемое имя тега — если тег привязан к ads (Tag#ad),
  # предпочитаем Ad#display_name ("Egypt"), иначе обычный перевод/name.
  def display_name(tag)
    tag.ad&.display_name || tag.translation(home_language)
  end

  TAG_PLACEHOLDER_FIELDS = %w[name slug short short_2].freeze

  # %{prefix}/%{prefix.name}/%{prefix.slug}/%{prefix.short}/%{prefix.short_2}
  # для заданного тега — либо, если tag нет (entity не помечена этим
  # уровнем), те же ключи с "" — чтобы шаблон, ссылающийся на уровень,
  # которого у entity нет, не падал с KeyError и не рушил весь прогон
  # каскада, а просто не подставил ничего.
  def tag_placeholders(prefix, tag)
    placeholders = { prefix.to_sym => tag ? display_name(tag) : "" }
    TAG_PLACEHOLDER_FIELDS.each { |field| placeholders[:"#{prefix}.#{field}"] = tag ? tag.public_send(field) : "" }
    placeholders
  end

  # Плейсхолдеры под именем каждой настроенной location-группы
  # (%{addressCountry.short}, %{adm_2.slug}, ...) — по ВСЕМ
  # location_levels сразу, не только по текущему (пусто, если entity
  # этим уровнем не помечена). Плюс %{location.*} — алиас на тег
  # ТЕКУЩЕГО уровня (удобнее в hub_fields/facet_fields, чтобы не
  # повторять имя группы).
  def base_placeholders(tags_by_level, current_level_tag)
    placeholders = location_levels.each_with_object({}) do |level, hash|
      hash.merge!(tag_placeholders(level, tags_by_level[level]))
    end
    placeholders.merge!(tag_placeholders("location", current_level_tag))
  end

  FIELD_NAMES = %w[title h1 subtitle anchor_1 anchor_2 anchor_3].freeze

  # Рендерит title/h1/subtitle/anchor_1-3 из hub_fields[level] или
  # facet_fields[level] (этого каскада — свой набор шаблонов на каждый
  # location_level), подставляя плейсхолдеры (см. tag_placeholders).
  # Пустой/отсутствующий шаблон — поле не заполняется (nil); пустое
  # поле тега (например short_2) даёт в тексте "" — не ошибка.
  def rendered_fields(templates_key, level, placeholders)
    templates = (@config[templates_key] || {})[level] || {}

    FIELD_NAMES.each_with_object({}) do |field, attrs|
      template = templates[field]
      attrs[field.to_sym] = template.presence && (template % placeholders)
    end
  end

  # Возвращает [page, :created|:updated|:skipped] — нужно run, чтобы
  # посчитать реально новые/обновлённые страницы для сводки run_all.
  # force: false — существующую страницу не трогает (:skipped), чтобы
  # не затереть ручные правки; force: true — обновляет её всеми полями.
  def ensure_hub_page(level, tag, tags_by_level, force)
    existing = root_page.children.find_by(slug: tag.slug)
    return [existing, :skipped] if existing && !force

    attrs = {
      lang: home_language,
      parent: root_page,
      slug: tag.slug,
      view: view_for("hub_fields", level),
      layout: layout_for("hub_fields", level),
      published: true,
      conditions: { "object" => "Entity", "schema" => trigger_schemas, "tags" => tag.slug }
    }.merge(rendered_fields("hub_fields", level, base_placeholders(tags_by_level, tag)))

    if existing
      existing.update!(attrs)
      [existing, :updated]
    else
      [Page.create!(attrs), :created]
    end
  end

  def ensure_facet_page(level, hub_page, facet_tag, location_tag, tags_by_level, force)
    existing = hub_page.children.find_by(slug: facet_tag.slug)
    return [existing, :skipped] if existing && !force

    attrs = {
      lang: home_language,
      parent: hub_page,
      slug: facet_tag.slug,
      view: view_for("facet_fields", level),
      layout: layout_for("facet_fields", level),
      published: true,
      conditions: { "object" => "Entity", "schema" => trigger_schemas, "tags" => ["and", location_tag.slug, facet_tag.slug] }
    }.merge(rendered_fields("facet_fields", level, base_placeholders(tags_by_level, location_tag).merge(tag_placeholders("facet", facet_tag))))

    if existing
      existing.update!(attrs)
      [existing, :updated]
    else
      [Page.create!(attrs), :created]
    end
  end
end
