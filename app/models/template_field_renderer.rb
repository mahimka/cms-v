# Рендерит текст поля PageTemplate (slug/title/h1/body/...).
#
# pageable — обычно Entity/Item/Event (template_type == "Profile", одна
# страница на объект). Но это может быть и Tag (template_type == "List"
# — PageTemplateGenerator рендерит поля List-страницы для группирующего
# тега, а не для объекта, см. #matching_tags_for) — {attr} работает
# одинаково в обоих случаях (public_send на любой ActiveRecord-объект),
# а тег-блок при pageable == Tag возвращает сам этот тег (см. ниже),
# а не выборку его тегов.
#
# Два вида плейсхолдеров:
#
#   {name}  — object.public_send(:name) (любой публичный атрибут/метод
#             объекта, не только name)
#
#   {details.email} — object.details["email"] (Hash {label.name => value},
#             см. Entity/Item/Event#details — обратная совместимость со
#             старым serialize :details). Значение — как есть, без
#             экранирования (details хранит простой текст, не html).
#
#   ["addressCountry"]
#   ["addressCountry", col: "name", limit: 1, delimiter: ", ",
#     before: "", after: "", before_tag: "", after_tag: "", if_empty: ""]
#           — теги объекта из группы "addressCountry" (Tag с
#             parent.name == "addressCountry"), отсортированы по
#             position, name. col — какое поле тега брать (name/slug/
#             short/short_2/id, по умолчанию name); тег есть, но само
#             поле у него пустое (например short не заведён) — фолбэк
#             на name, а не пустая строка. limit — сколько
#             тегов взять (по умолчанию 1 — "первый"). delimiter — чем
#             склеивать несколько. before/after — обрамляют весь блок,
#             before_tag/after_tag — каждый тег. if_empty — что вывести,
#             если у объекта нет ни одного тега этой группы (полностью
#             заменяет блок, before/after не применяются).
#
#             pageable == Tag (List) — блок своей же группы возвращает
#             сам pageable (см. #tags_for_group). Блок ЧУЖОЙ группы —
#             ищет в extra_tags (вложенный List, см. PageTemplateGenerator
#             class-comment: теги facet-предков по Page#list_tag_id) —
#             так child-template с своей группой "Lessons" может в
#             любом поле сослаться на группу РОДИТЕЛЯ, например
#             ["addressCountry"].
#
#   ["link:website", col: "url", ...]
#           — тот же блок, но первый аргумент с префиксом "link:" —
#             ссылки объекта (Entity/Item/Event#links) с label.name ==
#             "website" (facebook/instagram/website/youtube и т.п.).
#             col — только "url" (по умолчанию). Опции limit/delimiter/
#             before/after/before_tag/after_tag/if_empty — те же, что у
#             тегов.
#
#   ["profile:google.com", col: "rating", ...]
#           — префикс "profile:" — профили объекта (Entity/Item/Event#
#             profiles, см. Profile) на сайте с этим Site#domain ИЛИ
#             Site#name (что совпадёт — "google.com" и "Google Maps"
#             дадут одно и то же). col — rating/review_count/url/title/
#             h1/meta_description (по умолчанию rating). rating/
#             review_count у профиля могут быть ещё не заполнены
#             (заполняются парсером) — тогда просто пусто, если_empty
#             сработает только когда самого профиля с таким сайтом нет.
#
# Блоки link:/profile: работают только когда pageable — Entity/Item/
# Event (у Tag нет ни links, ни profiles) — иначе пусто (if_empty).
#
# НЕ eval — опции разбираются вручную регулярками, без исполнения кода
# (template — админский, но лишний eval на пользовательский текст ни к
# чему).
class TemplateFieldRenderer
  ATTRIBUTE_RE = /\{([\w.]+)\}/.freeze
  TAG_BLOCK_RE = /\[([^\[\]]*)\]/m.freeze
  TAG_GROUP_RE = /\A\s*"((?:[^"\\]|\\.)*)"\s*(?:,\s*(.*))?\z/m.freeze
  OPTION_RE = /(\w+)\s*:\s*(?:"((?:[^"\\]|\\.)*)"|(-?\d+))\s*,?/.freeze
  TAG_FIELDS = %w[name slug short short_2 id].freeze
  LINK_FIELDS = %w[url].freeze
  PROFILE_FIELDS = %w[rating review_count url title h1 meta_description].freeze

  def initialize(pageable, extra_tags: [])
    @pageable = pageable
    @extra_tags = extra_tags
  end

  def render(template)
    return "" if template.blank?

    result = template
      .gsub(TAG_BLOCK_RE) { render_tag_block(Regexp.last_match(1)) }
      .gsub(ATTRIBUTE_RE) { render_attribute(Regexp.last_match(1)) }

    # Блок с if_empty: "" (частый случай у profile: — рейтинга ещё нет)
    # оставляет в многострочном теле пустую строку на своём месте —
    # схлопываем 3+ подряд идущих переноса (пустая строка + ещё одна)
    # до одного абзацного отступа, а не заставляем автора городить
    # вычисления "будет ли тут вообще что-то" в самом тексте.
    result.gsub(/\n[ \t]*(?:\n[ \t]*)+/, "\n\n").strip
  end

  # Имя первой группы тегов, на которую ссылается шаблон (первый
  # распознанный тег-блок вида ["группа", ...]) — nil, если блоков нет
  # или ни один не распознан. Используется PageTemplateGenerator для
  # List: по какой группе группировать объекты выборки, чтобы получить
  # "массив полученных значений выборки" (см. class-comment PageTemplateGenerator).
  def self.referenced_group(template)
    return nil if template.blank?

    template.to_s.scan(TAG_BLOCK_RE) do |match|
      parsed = parse_tag_block(match[0])
      return parsed[:group] if parsed
    end

    nil
  end

  # Все группы тегов (обычных, не link:/profile:), на которые ссылается
  # шаблон — без повторов, в порядке первого появления. Используется
  # PageTemplateGenerator для List, чтобы найти "соседние" теги других
  # групп у объектов с текущим группирующим тегом (см. PageTemplateGenerator
  # #sibling_tags) — например, у List по "addressRegion" в title сослались
  # ["addressCountry"] — без этого он не резолвился бы: объект несёт оба
  # тега одновременно, но группирующий тег объекта тут не сам объект.
  def self.referenced_groups(template)
    return [] if template.blank?

    groups = []
    template.to_s.scan(TAG_BLOCK_RE) do |match|
      parsed = parse_tag_block(match[0])
      next unless parsed
      next if parsed[:group].start_with?("link:", "profile:")

      groups << parsed[:group]
    end

    groups.uniq
  end

  private

  def render_attribute(attr)
    return render_detail(attr.sub("details.", "")) if attr.start_with?("details.")

    @pageable.respond_to?(attr) ? @pageable.public_send(attr).to_s : ""
  end

  # details — Hash {label.name => value} (см. Entity/Item/Event#details).
  def render_detail(key)
    return "" unless @pageable.respond_to?(:details)

    @pageable.details[key].to_s
  end

  def render_tag_block(content)
    parsed = self.class.parse_tag_block(content)
    return "[#{content}]" unless parsed # не похоже на наш формат — оставляем как в исходнике

    group = parsed[:group]
    items, fields, default_col =
      if group.start_with?("link:")
        [links_for(group.delete_prefix("link:")), LINK_FIELDS, "url"]
      elsif group.start_with?("profile:")
        [profiles_for(group.delete_prefix("profile:")), PROFILE_FIELDS, "rating"]
      else
        [tags_for_group(group), TAG_FIELDS, "name"]
      end

    render_items(parsed, items, fields, default_col)
  end

  def render_items(parsed, items, fields, default_col)
    col = fields.include?(parsed[:col]) ? parsed[:col] : default_col
    limit = (parsed[:limit] || "1").to_i
    delimiter = parsed[:delimiter] || ", "
    before = parsed[:before] || ""
    after = parsed[:after] || ""
    before_tag = parsed[:before_tag] || ""
    after_tag = parsed[:after_tag] || ""
    if_empty = parsed[:if_empty] || ""

    # Пропускаем записи, у которых само значение col пусто (частый случай
    # у profile: rating/review_count заполняются парсером не сразу) — не
    # выводить пустое before_tag/after_tag ради ничего. Если ПОСЛЕ этого
    # ничего не осталось — if_empty (тег таким никогда не сработает,
    # item_value для Tag сам подставляет name вместо пустого col; для
    # link col="url" всегда заполнен — так что для них это no-op).
    values = items.limit(limit).filter_map { |item| item_value(item, col).presence }
    return if_empty if values.empty?

    values = values.map { |value| "#{before_tag}#{value}#{after_tag}" }
    "#{before}#{values.join(delimiter)}#{after}"
  end

  # Тег есть, но поле col у него не заполнено (частый случай — short/
  # short_2 заводят не для всех тегов) — фолбэк на name, а не пустая
  # строка: тег есть, значит есть что показать. Link/Profile такого
  # запасного поля не имеют — просто значение как есть.
  def item_value(item, col)
    value = item.public_send(col)
    return value.to_s unless item.is_a?(Tag)

    value.presence || item.name
  end

  def links_for(label_name)
    return Link.none unless @pageable.respond_to?(:links)

    @pageable.links.joins(:label).where(labels: { name: label_name }).active
  end

  def profiles_for(site_ident)
    return Profile.none unless @pageable.respond_to?(:profiles)

    @pageable.profiles.joins(:site).where("sites.domain = :v OR sites.name = :v", v: site_ident).active
  end

  # pageable — обычная запись (Entity/Item/Event): её собственные теги
  # этой группы, как раньше.
  #
  # pageable — Tag (List-рендер, см. class-comment): "своих" тегов у
  # тега нет — если группа блока совпадает с группой самого pageable
  # (parent.name), это ссылка на него самого (ровно один тег — он сам).
  # Иначе ищем в extra_tags (теги facet-предков вложенного List, см.
  # class-comment) — первый с подходящей группой. Не нашли нигде — пусто
  # (сработает if_empty).
  def tags_for_group(group)
    if @pageable.is_a?(Tag)
      return Tag.where(id: @pageable.id) if @pageable.parent&.name == group

      extra = @extra_tags.find { |tag| tag.parent&.name == group }
      extra ? Tag.where(id: extra.id) : Tag.none
    else
      @pageable.tags.joins(:parent).where(parent: { name: group }).order(:position, :name)
    end
  end

  # ["group", key: "value", key: 123, ...] -> {group:, key: "value"|"123"}
  def self.parse_tag_block(content)
    match = TAG_GROUP_RE.match(content)
    return nil unless match

    options = { group: unescape(match[1]) }
    match[2].to_s.scan(OPTION_RE) do |key, str_val, num_val|
      options[key.to_sym] = str_val.nil? ? num_val : unescape(str_val)
    end
    options
  end

  def self.unescape(str)
    str.gsub('\\"', '"')
  end
end
