# Генерирует страницы по PageTemplate. Два template_type:
#
# "Profile" — detail-страница на каждый объект выборки (Pageable-
# конвенция: ищем существующую через object.page). slug/title/...
# рендерятся TemplateFieldRenderer, привязанным к самому объекту.
#
# "List" — не по одной странице на объект, а по одной странице на
# КАЖДОЕ РАЗЛИЧНОЕ значение группы тегов, встреченное среди объектов
# выборки (та же выборка, что у Profile — см. #matching_objects; группа
# берётся из первого тег-блока в поле slug, см.
# TemplateFieldRenderer.referenced_group — например slug вида
# ["addressCountry", col: "slug"] группирует по тегам группы
# addressCountry: если среди объектов выборки встретились теги "egypt"
# и "oman" этой группы — получится 2 страницы). slug/title/...
# рендерятся TemplateFieldRenderer, привязанным к САМОМУ ТЕГУ группы
# (не к объекту — общего "объекта" у списочной страницы нет), поле
# conditions — точно так же (тот же формат, что template_conditions —
# TagExpression AST/строка), оборачивается в Page#conditions-hash
# {"object" => pageable_type, "schema" => [...], "tags" => <рендер>};
# если внутри conditions нужно сузить список до именно этого значения
# группы — сошлитесь на ту же группу explicit-плейсхолдером, как в
# slug (["addressCountry", col: "slug"]), автоматически generator это
# не подставляет. Найденная существующая страница — по (template_id,
# parent, slug): у списочной страницы нет своего pageable-объекта,
# чтобы искать через него, а slug для конкретного тега детерминирован
# между запусками.
#
# Вложенный List (PageTemplate#parent_template, обязательно тоже
# "List") — facet-страницы ПОД КАЖДОЙ страницей родительского
# template'а, а не под одним статичным parent_page: для template #4
# (страны, /egypt, /oman, ...) child-template со slug
# ["Lessons", col: "slug"] создаст /egypt/{lessons-facet},
# /oman/{lessons-facet} и т.д. — по одной группе facet-страниц НА
# КАЖДУЮ страницу родителя, а не одну общую. Область объектов для
# группировки и для итогового conditions — Page#list_objects родительской
# страницы (её собственная, уже отфильтрованная выборка), пересечённая
# с template_conditions ДОЧЕРНЕГО template'а — которое поэтому здесь,
# в отличие от верхнеуровневого template'а, МОЖЕТ быть пустым (значит
# "без доп. фильтра, взять всё из родителя", см. #matching_objects).
# parent_page_id дочернего template'а при этом игнорируется — родитель
# всегда конкретная facet-страница, вычисленная для каждой группы отдельно.
#
# Каждая List-страница запоминает свой группирующий тег в
# Page#list_tag_id. Это даёт вложенным child-template'ам доступ к
# тегам ВСЕХ facet-предков (не только своей группы) — например
# child со своей группой "Lessons" в любом поле (title/h1/slug/...)
# может сослаться на группу родителя, ["addressCountry"]: генератор
# поднимается по Page#path и собирает list_tag_id — см. #ancestor_tags,
# TemplateFieldRenderer extra_tags.
#
# Ещё один источник extra_tags — БЕЗ вложенности, в пределах одного
# template'а: List по группе "addressRegion" со ссылкой ["addressCountry"]
# в title — объект (Entity) обычно несёт сразу оба гео-тега одновременно,
# генератор находит соответствующий addressCountry-тег среди объектов,
# у которых есть текущий addressRegion-тег, см. #sibling_tags.
#
# Объекты pageable_type отбираются через template_conditions — тот же
# формат (и движок — TagExpression), что у Page#conditions["tags"]:
# строка или AST ["and"/"or"/"not", ...] по slug/name тегов. Пустое
# значение — не строгий фильтр (задать явно, но не сузить нечем), а
# "все объекты pageable_type" (единственное реальное ограничение тогда
# — schema_id, если задан).
#
# force: false (по умолчанию) — существующие страницы не трогает (часто
# правятся руками). force: true — обновляет все поля по текущему template.
class PageTemplateGenerator
  def self.run(page_template, force: false)
    new(page_template).run(force: force)
  end

  def initialize(page_template)
    @page_template = page_template
  end

  FIELD_NAMES = %w[
    title h1 subtitle meta_description body faq schema
    anchor_1 anchor_2 anchor_3
    hero_1 hero_2 hero_3
    sidebar_1 sidebar_2 sidebar_3
    footer_1 footer_2 footer_3
    block_1 block_2 block_3 block_4 block_5 block_6
  ].freeze

  # Возвращает {created: [...], updated: [...], skipped: [...]}.
  def run(force: false)
    case @page_template.template_type
    when "Profile" then run_profile(force)
    when "List" then run_list(force)
    else { created: [], updated: [], skipped: [] }
    end
  end

  private

  def run_profile(force)
    results = { created: [], updated: [], skipped: [] }
    matching_objects.find_each do |object|
      page, status = ensure_page(object, force)
      results[status] << page
    end
    results
  end

  def run_list(force)
    results = { created: [], updated: [], skipped: [] }
    list_targets.each do |parent_for_group, objects_scope|
      group_tags(objects_scope).each do |tag|
        page, status = ensure_list_page(tag, parent_for_group, objects_scope, force)
        results[status] << page
      end
    end
    results
  end

  def nested?
    @page_template.parent_template.present? && @page_template.parent_template.template_type == "List"
  end

  # [[parent_page, objects_scope], ...] — на каждый элемент одна пачка
  # facet-групп. Без parent_template — один элемент на весь template
  # (статичный parent_page + вся matching_objects, как раньше). С ним —
  # по элементу на КАЖДУЮ уже сгенерированную страницу родительского
  # template'а (см. class-comment).
  #
  # Раньше здесь был N+1: parent.list_objects на каждую родительскую
  # страницу — свежий TagExpression + published-подзапрос ПО ОДНОМУ
  # родителю (на addressLocality с 2000+ страниц это тысячи запросов,
  # каждый по вложенным IN(...) — минуты вместо секунд). У всех
  # родителей, чьи effective_conditions["tags"] это просто имя ОДНОГО
  # тега (весь текущий набор template'ов — 2/3/4 с пустым
  # template_conditions, other case не встречается) — считаем
  # object_id -> parent_tag_id ОДНИМ запросом на всех сразу. Родителей
  # со составным AST (в теории — многоуровневая вложенность с
  # доп.фильтром) — по старой, гарантированно корректной, но медленной
  # схеме (их в реальных данных сейчас нет).
  def list_targets
    return [[parent_page, matching_objects]] unless nested?

    klass = @page_template.pageable_type.to_s.constantize
    parent_pages = Page.where(template_id: @page_template.parent_template_id).to_a
    return [] if parent_pages.empty?

    simple_parents, complex_parents = parent_pages.partition do |parent|
      parent.list_tag_id.present? && parent.effective_conditions["tags"].is_a?(String)
    end

    targets = []

    if simple_parents.any?
      tag_ids = simple_parents.map(&:list_tag_id)

      ids_by_tag_id = Tagging
        .where(tag_id: tag_ids, taggable_type: klass.name, taggable_id: matching_objects.select(:id))
        .pluck(:tag_id, :taggable_id)
        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(tag_id, obj_id), h| h[tag_id] << obj_id }

      # Тот же published-фильтр, что и в ListQuery#objects (см.
      # list_query.rb) — раньше он неявно применялся внутри
      # parent.list_objects на каждого родителя по отдельности, теперь
      # считаем один раз и пересекаем в памяти (маленькие массивы на тег).
      published_ids = klass.include?(Pageable) ? Page.where(pageable_type: klass.name, published: true).pluck(:pageable_id).to_set : nil

      simple_parents.each do |parent|
        ids = ids_by_tag_id[parent.list_tag_id]
        next if ids.blank?

        ids = ids.select { |id| published_ids.include?(id) } if published_ids
        next if ids.empty?

        targets << [parent, klass.where(id: ids)]
      end
    end

    complex_parents.each do |parent|
      targets << [parent, parent.list_objects.where(id: matching_objects.select(:id))]
    end

    targets
  end

  def matching_objects
    klass = @page_template.pageable_type.to_s.constantize
    # Entity/Item/Event имеют scope :generate_pages, Picture — :active —
    # объекты, снятые с генерации (сняты с публикации/в архиве), страницы
    # получать не должны, тот же принцип, что у ListQuery#objects.
    base = klass.respond_to?(:generate_pages) ? klass.generate_pages : (klass.respond_to?(:active) ? klass.active : klass.all)
    scope =
      if @page_template.template_conditions.blank?
        base
      else
        base.where(id: TagExpression.new(parsed_conditions).matching_ids(klass).to_a)
      end
    scope = scope.where(schema_id: schema_ids_with_subtree) if @page_template.schema_id.present? && klass.column_names.include?("schema_id")
    scope
  end

  # schema_id — доп. фильтр к template_conditions, с поддеревом (тот же
  # принцип, что у ListQuery: выбрал LodgingBusiness — заберёт и Hotel).
  def schema_ids_with_subtree
    @page_template.filter_schema.subtree.pluck(:id)
  end

  # template_conditions — строка (одиночный tag) или JSON-массив
  # (["and"/"or"/"not", ...], см. TagExpression) — тот же формат, что
  # руками пишут в Page#conditions["tags"].
  def parsed_conditions
    parse_ast(@page_template.template_conditions)
  end

  # Page#calculated_uri отдаёт "/" для ЛЮБОЙ страницы без родителя —
  # если parent_page не выбран, страницы бы схлопнулись в один uri.
  # Фолбэк — корень сайта на языке template. Не используется, когда
  # template вложен (#nested?) — там у каждой группы свой parent, см.
  # #list_targets.
  def parent_page
    @page_template.parent_page || Page.masters.roots.find_by!(lang: @page_template.lang)
  end

  def ensure_page(object, force)
    existing = object.respond_to?(:page) ? object.page : nil
    return [existing, :skipped] if existing && !force

    renderer = TemplateFieldRenderer.new(object)

    attrs = base_attrs(renderer, parent_page).merge(
      pageable_type: @page_template.pageable_type,
      pageable_id: object.id
    )

    save_page(existing, attrs, force, object)
  end

  # Группа тегов, по которой строится List — берётся из первого
  # тег-блока в slug (см. class-comment). Без неё List строить не из
  # чего — каждая "страница" схлопнулась бы в одну без явного различия.
  def list_group
    TemplateFieldRenderer.referenced_group(@page_template.slug)
  end

  # Различные значения этой группы тегов, реально встреченные среди
  # объектов objects_scope — "массив полученных значений выборки"
  # (задание пользователя дословно). По одной List-странице на каждое.
  def group_tags(objects_scope)
    group = list_group
    return Tag.none if group.blank?

    klass = @page_template.pageable_type.to_s.constantize
    Tag
      .joins(:parent, :taggings)
      .where(parent: { name: group })
      .where(taggings: { taggable_type: klass.name, taggable_id: objects_scope.select(:id) })
      .distinct
      .order(:position, :name)
  end

  def ensure_list_page(tag, parent_for_group, objects_scope, force)
    extra = ancestor_tags(parent_for_group) + sibling_tags(tag, objects_scope)
    renderer = TemplateFieldRenderer.new(tag, extra_tags: extra)
    slug = SlugGenerator.call(renderer.render(@page_template.slug))

    # has_ancestry — parent_id не колонка, ищем через ancestry (см.
    # Ancestry#child_ancestry — то значение ancestry, которое было бы
    # у прямого потомка parent_for_group). Ищем по list_tag_id, а НЕ по
    # slug — slug у самого тега может со временем поменяться (например
    # синхронизация с geonames.db), и поиск по нему тогда не найдёт уже
    # существующую страницу и наплодит дубликат вместо update (баг,
    # словленный именно на этом — см. tags:sync_geoname_slug).
    existing = Page.find_by(template_id: @page_template.id, ancestry: parent_for_group.child_ancestry, list_tag_id: tag.id)
    return [existing, :skipped] if existing && !force

    attrs = base_attrs(renderer, parent_for_group).merge(
      slug: slug,
      list_tag_id: tag.id,
      conditions: conditions_hash(renderer, parent_for_group)
    )

    save_page(existing, attrs, force, tag)
  end

  # Теги всех facet-предков parent_for_group (её самой и её собственных
  # предков) — Page#list_tag_id, если задан (у не-List-страниц — nil,
  # .compact их убирает). См. class-comment: нужно, чтобы вложенный
  # child-template мог в своих полях сослаться на группу родителя.
  def ancestor_tags(parent_for_group)
    ids = parent_for_group.path.pluck(:list_tag_id).compact
    return [] if ids.empty?

    Tag.where(id: ids).to_a
  end

  # Теги ДРУГИХ групп (упомянутых где-либо в полях template'а), реально
  # встреченные у объектов, несущих именно tag — объект обычно несёт
  # сразу несколько геотегов одновременно (addressCountry И addressRegion
  # у одного Entity), а рендерер List привязан только к группирующему
  # тегу (tag), поэтому без этого ["addressCountry"] в title у List по
  # "addressRegion" не резолвился бы, хотя у самих объектов такой тег есть.
  def sibling_tags(tag, objects_scope)
    groups = referenced_groups - [list_group]
    return [] if groups.empty?

    klass = @page_template.pageable_type.to_s.constantize
    ids_with_tag = objects_scope.joins(:tags).where(tags: { id: tag.id }).select(:id)

    Tag
      .joins(:parent, :taggings)
      .where(parent: { name: groups })
      .where(taggings: { taggable_type: klass.name, taggable_id: ids_with_tag })
      .distinct
      .order(:position, :name)
      .to_a
  end

  # Все группы тегов, на которые ссылаются поля template'а — не только
  # slug (как #list_group), а title/h1/conditions/... тоже.
  def referenced_groups
    fields = [@page_template.slug, @page_template.conditions] + FIELD_NAMES.map { |f| @page_template.public_send(f) }
    fields.flat_map { |f| TemplateFieldRenderer.referenced_groups(f) }.uniq
  end

  # Page#conditions — Hash, который резолвит ListQuery (см. её
  # class-comment): "object"/"schema" уже заданы на уровне template
  # (pageable_type/filter_schema) — их не нужно повторять в поле
  # conditions, там только "tags" (тот же формат, что template_conditions).
  #
  # Вложенный template (#nested?) — свой рендер conditions (если
  # непустой — доп. фильтр, например конкретная facet-группа) АВТОМАТИЧЕСКИ
  # AND'ится с "tags" родительской facet-страницы: без этого не выразить
  # "то же, что у родителя" в статичном тексте поля — у каждой группы
  # родителя (egypt/oman/...) свой тег, а шаблон один на все.
  def conditions_hash(renderer, parent_for_group)
    own_tags = parse_ast(renderer.render(@page_template.conditions))
    tags = nested? ? combine_tags(parent_for_group.effective_conditions["tags"], own_tags) : own_tags

    hash = { "object" => @page_template.pageable_type, "tags" => tags }
    hash["schema"] = [@page_template.filter_schema.name] if @page_template.schema_id.present?
    hash
  end

  def combine_tags(parent_tags, own_tags)
    return parent_tags if own_tags.blank?
    return own_tags if parent_tags.blank?

    ["and", parent_tags, own_tags]
  end

  def base_attrs(renderer, parent)
    attrs = {
      lang: @page_template.lang,
      parent: parent,
      slug: SlugGenerator.call(renderer.render(@page_template.slug)),
      template_id: @page_template.id,
      view: @page_template.view,
      layout: @page_template.layout
    }

    FIELD_NAMES.each { |field| attrs[field.to_sym] = renderer.render(@page_template.public_send(field)) }
    attrs
  end

  def parse_ast(rendered)
    JSON.parse(rendered)
  rescue JSON::ParserError, TypeError
    rendered
  end

  def save_page(existing, attrs, force, object)
    if existing
      # ready/published НЕ трогаем при обновлении — это решение админа
      # (опубликовал/снял с публикации вручную после генерации), а не
      # то, что должен молча перезатирать force refresh. Раньше это
      # безусловно ставилось из page_template на каждый прогон — тихо
      # СНИМАЛО публикацию с уже опубликованных страниц (page_published
      # у template часто false) и попутно ломало запись в History
      # (Page#record_own_uri_history триггерится по published? ПОСЛЕ
      # сохранения — если тут же гасим published, редирект при смене
      # uri не запишется).
      #
      # Поля, которые правили руками (Page#edited_columns) — force
      # refresh их тоже не трогает.
      protected_fields = Array(existing.edited_columns).map(&:to_sym)
      existing.update!(attrs.except(*protected_fields))
      [existing, :updated]
    else
      # ready/published — только при первом создании страницы.
      attrs[:ready] = @page_template.page_ready
      attrs[:published] = @page_template.page_published
      [create_page_disambiguating_slug(attrs, object), :created]
    end
  end

  # slug из name (Profile) не уникален — сплошь и рядом несколько разных
  # Entity с одинаковым названием ("Yoga Studio" в десятке городов), а
  # Page#uri обязан быть уникален. При коллизии uri пробуем по очереди
  # уточнить slug городом (addressLocality), потом страной
  # (addressCountry), и в конце — object.id: он уникален всегда, поэтому
  # цепочка гарантированно где-то остановится, а не свалится в 404.
  # У List-страниц (object — Tag, а не Entity) slug и так уникален
  # (Tag#slug), так что до этих уточнений реально не доходит.
  def create_page_disambiguating_slug(attrs, object)
    base_slug = attrs[:slug]
    suffixes = disambiguation_suffixes(object)

    begin
      Page.create!(attrs)
    rescue ActiveRecord::RecordInvalid => e
      raise if suffixes.empty? || e.record.errors[:uri].blank?

      attrs = attrs.merge(slug: SlugGenerator.call("#{base_slug} #{suffixes.shift}"))
      retry
    end
  end

  def disambiguation_suffixes(object)
    suffixes = []

    if object.respond_to?(:tags_of_group)
      suffixes << object.tags_of_group('addressLocality').first&.name
      suffixes << object.tags_of_group('addressCountry').first&.name
    end

    (suffixes.compact << object.id).uniq
  end
end
