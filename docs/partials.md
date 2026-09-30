# Партиалы для ссылок-списков (app/views/partials)

Справка по partial'ам, сделанным/переработанным в ходе работы над
гео-иерархией (country/region/locality), facet-страницами и
производительностью списков ссылок.

Общий паттерн у всех "списков ссылок" ниже: считать
`counts = Page.batch_list_objects_counts(pages)` **одним** запросом на
весь список перед циклом и передавать `count:` в `_page_link_with_count`
— без этого на каждую ссылку уходит отдельный `list_objects.count`
(было 400+ SQL-запросов на `/philippines`, см. `app/models/list_query.rb`
`ListQuery.batch_counts_for`).

## Общий строительный блок

### `_page_link_with_count`

Одна "таблетка" — ссылка + визуально выделенный счётчик объектов
(`tags has-addons`, `is-primary`). Сам по себе нигде напрямую не
используется — общий рендер-кирпичик для всех партиалов ниже.

- `target` (Page, обязательный)
- `label` (готовый текст ссылки, обязательный)
- `count` (число, желательно — без него посчитает `target.list_objects.count`
  сам, но тогда N+1 при вызове в цикле)
- `title` (необязательный tooltip)

Используется изнутри остальных партиалов ниже, не напрямую.

## Списки ссылок

Каждый выводит `<div class="field is-grouped is-grouped-multiline">` с
"таблетками" `_page_link_with_count`.

### `_geo_sibling_links`

На гео-странице (country/region) — ссылки на страницы "дочерней"
гео-группы (у country → регионы, у region → города). Ищет не через
дерево Page (у гео-страниц оно плоское), а через теги: какие ещё теги
`child_group` встречаются у объектов, помеченных текущим гео-тегом
страницы.

- `page` (по умолчанию `@page`)
- `child_group` (обязательный, имя группы тегов, напр. `"addressRegion"`)
- `anchor` (поле для текста ссылки, по умолчанию `'h1'`)

Используется: `country.erb` (`child_group: 'addressRegion'`),
`region.erb` (`child_group: 'addressLocality'`) — оба с
`anchor: 'anchor_1'`.

### `_facet_sibling_links`

На facet-странице вида `/innsbruck/ashtanga-yoga` — ссылки на
страницы-сиблинги той же группы под тем же родителем
(`/innsbruck/hatha-yoga`, `/innsbruck/vinyasa-yoga`...). Facet-страницы
одного nested-template'а физически сиблинги в дереве Page (общий
`template_id`+`ancestry`), поэтому один простой запрос без похода через
теги.

- `page` (по умолчанию `@page`)
- `anchor` (по умолчанию `'h1'`)

Используется: `country_tag.erb`, `region_tag.erb`, `locality_tag.erb` —
везде `anchor: 'anchor_1'`.

### `_page_children_links_by_group`

На гео-странице — ссылки на её facet-дочерние страницы, но только из
ОДНОЙ конкретной топикал-группы тегов (напр. "Yoga Style"), определяется
по `conditions["tags"]` дочерней страницы, а не по `page.children`
напрямую.

- `page` (по умолчанию `@page`)
- `group` (обязательный, имя группы тегов)
- `anchor` (по умолчанию `'h1'`)

Используется: `country.erb`, `region.erb`, `locality.erb` — в цикле по
всем корневым группам тегов (`Tag.where(parent_id: [nil, 0])`), каждая с
`anchor: 'anchor_1'`.

**Важно:** вызывать партиал один раз и переиспользовать результат —
двойной вызов (blank?-проверка + рендер) удваивает батч-запрос
счётчиков:

```erb
<% group_html = partial '_page_children_links_by_group', group: t_g.name, anchor: 'anchor_1' %>
<% unless group_html.blank? %>
  <%= group_html %>
<% end %>
```

### `_page_children_by_url`

Ссылки на ВСЕХ опубликованных детей произвольной страницы по её `url` —
без фильтра по группе тегов (в отличие от `_page_children_links_by_group`).
Для hub-страниц вроде `/yoga-styles`, не завязанных на гео-иерархию.

- `url` (обязательный, uri страницы, напр. `"/yoga-styles"`)
- `lang` (пока не используется — задел под мультиязычность)
- `anchor` (по умолчанию `'anchor_1'`)

Сейчас нигде не подключён (заменён на `_tag_group_links` в body главной),
но остаётся полезным инструментом для страниц без привязки к
`list_tag_id`.

### `_tag_group_links`

Ссылки на все опубликованные страницы конкретной ВЕРХНЕУРОВНЕВОЙ группы
тегов (`addressCountry` → `/austria`, `/argentina`...; `"Yoga Style"` →
`/yoga-styles/ashtanga-yoga`...). Ищет через `Tag`/`list_tag_id`, но
обязательно фильтрует по конкретному верхнеуровневому `PageTemplate`
этой группы (не просто по `list_tag_id`) — иначе цепляет ещё и
вложенные facet-страницы с тем же тегом (проверено на баге с
`/sri-lanka/ananda-yoga`, вылезавшим в списке наравне с
`/yoga-styles/ananda-yoga`).

- `group` (обязательный, имя корневой группы тегов)
- `anchor` (по умолчанию `'anchor_1'`)

Используется: `Page#1.body` (главная страница) — дважды: `group:
'addressCountry'` (через обёртку `_countries_list`) и `group: 'Yoga
Style'` напрямую.

### `_countries_list`

Тонкая обёртка над `_tag_group_links` с `group: 'addressCountry'` —
оставлена отдельным именем, т.к. уже вшита в текст `Page#1.body`.

Без параметров.

Используется: `Page#1.body`, секция "Browse yoga by location".

## Пагинация (изменён, не создан заново)

### `_list_paginated`

Сетка карточек объектов + пагинация. Изменено: пагинация теперь строит
ссылки вида `/argentina/2` вместо `?page=2` через
`paginate(paged_objects, base_path: @page&.uri)` (см.
`app/helpers/paginate_helpers.rb`).

- `objects` (по умолчанию `@objects`)
- `list_item` (партиал карточки, по умолчанию `'_card'`)
- `per` (по умолчанию 12)
- `anchor_suffix`

Используется везде, где уже стоял — без изменений на call-сайтах, вся
логика пути внутри партиала.
