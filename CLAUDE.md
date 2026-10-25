# cms-versatile

Самописная CMS на Sinatra + ActiveRecord + SQLite. Один и тот же движок
(этот репозиторий) запущен под несколько сайтов (diversorio.com,
istriada.com, kitezilla.com, pilotbook.com, pointnemo.com,
spiritcentral.com, triestia.com, yogamela.com) — у каждого сайта свой
клон этого же bare-репозитория (`origin`), общая ветка `master`.

## Мульти-сайтовость: что общее, а что локальное

- **Корень репозитория** (`app/`, `app.rb`, `config/`, `lib/`, `docs/`,
  этот `CLAUDE.md`) — общий код движка. Всё, что сюда коммитится и
  пушится в `origin`, разойдётся по **всем** сайтам при их следующем
  `git pull`. Поэтому в корень кладём только то, что одинаково нужно
  всем сайтам.
- **`project/`** — зона переопределений конкретного сайта: routes
  (`project/_routes.rb`), хелперы, views, lib, prompts, tasks,
  row-data. `project/.gitignore` игнорирует всё (`*`) и явно
  разрешает только эти пути — остальное (CSV с данными, `backups/` и
  т.п.) живёт только на диске этого сайта и никогда не коммитится.
- Если нужны заметки/инструкции, специфичные только для одного сайта
  (не для движка), держите свой `project/CLAUDE.md` — он не попадёт
  под allow-list `project/.gitignore`, значит не закоммитится и не
  разъедется по другим сайтам.

## Структура движка

- `app.rb` — точка входа Sinatra-приложения, конфигурация, подключения
  к доп. базам (`db/gsc.db` — статистика Google Search Console,
  `db/geonames.db` — локальная копия geonames.org).
- `app/models/` — доменные модели (см. ниже).
- `app/controllers/` — по контроллеру на ресурс (`entities_controller.rb`,
  `pages_controller.rb`, `page_templates_controller.rb`, `tags_controller.rb`
  и т.д.) + `routes.rb`, `routes_history.rb`, `routes_lost.rb`.
- `app/views/` — общие (admin + публичные) шаблоны; `project/views/`
  переопределяет/добавляет публичные шаблоны конкретного сайта.
- `config/` — `*.yml`/`*.rb` конфиги не в git (кроме `_`-префиксных
  шаблонов-примеров, см. `.gitignore`); реальные `config.yml`,
  `secret.yml` и т.п. — локальные для каждого сайта.

## Доменная модель

- **`Entity`** — основная сущность контента (отель, ресторан,
  достопримечательность и т.п.), типизируется через `belongs_to :schema`
  (см. `Schema`, построен по иерархии schema.org). Поддерживает
  `parent`/`children` (ancestry через `parent_id`, см.
  `docs/TEMPLATES_PARENT.md`), `Tag`-и, `Detail`-ы (произвольные
  key-value поля), `Profile`-и, `Link`-и, `Picture`-ы.
- **`Item`**, **`Event`** — другие pageable-типы наравне с `Entity`
  (см. `PageTemplate::PAGEABLE_TYPES`).
- **`Tag`** — иерархический тег/категория (`parent`/`children`),
  группирует Entity/Item/Event через `Tagging`.
- **`Schema`** — тип сущности (иерархия, как schema.org), определяет
  допустимые теги/лейблы (`SchemaTag`, `SchemaLabel`) для формы
  редактирования Entity.
- **`Page`** — опубликованная страница сайта: либо создана вручную,
  либо сгенерирована из `PageTemplate` (`PageTemplateGenerator`).
  Поддерживает ancestry, переводы (`TRANSLATABLE_FIELDS`,
  `PageTranslator`), редиректы при смене URL (`History`, `LostUrl`).
- **`PageTemplate`** — шаблон генерации страниц: типы `Profile`
  (одна страница на объект), `ProfileUri`, `List` (facet/листинговые
  страницы, может быть вложен в `parent_template` — см. комментарий
  в `page_template.rb`). Поля шаблона (`slug`, `title`, `body`,
  `hero_*`, `block_*` и т.д.) рендерит **`TemplateFieldRenderer`** —
  полный синтаксис (`{attr}`, `{details.x}`, `[tag]`, `["link:..."]`,
  доступ к родителю через `parent.`/`parent:`) описан в
  `docs/TEMPLATES_PARENT.md` и в комментарии в начале
  `app/models/template_field_renderer.rb`.
- **`SnapShot`** — служебные снимки/история импортов.
- **`Geoname`** — читает отдельную БД `db/geonames.db`, не создаёт
  собственных записей.

## Конвенции

- Комментарии в коде — на русском, объясняют **почему** (неочевидные
  решения, грабли, которые уже наступали), а не что делает код.
- Не используем `eval` при рендере шаблонов — всё разбирается
  регулярками (см. `docs/TEMPLATES_PARENT.md`).
- При изменении `project/_routes.rb`/`project/views` — это специфика
  одного сайта, не трогайте общий код движка для частных нужд одного
  сайта без необходимости (иначе это разъедется на остальные через
  git).

## Подробные инструкции

@docs/TEMPLATES_PARENT.md
@docs/partials.md
