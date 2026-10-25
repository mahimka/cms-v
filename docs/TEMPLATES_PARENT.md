# Родитель в шаблонах страниц

В полях `PageTemplate` (slug, title, h1, body, faq, hero_*, block_* и т.д.) можно ссылаться не только на сам объект, но и на его родителя — `Entity#parent` (например, линию у круизного судна). Рендерит поля `TemplateFieldRenderer` (`app/models/template_field_renderer.rb`), страницы по шаблону создаёт `PageTemplateGenerator`.

## Коротко

| Нужно | Пишем |
|---|---|
| Атрибут родителя | `{parent.name}` |
| Detail родителя | `{parent.details.passengers}` |
| Адрес страницы родителя | `{parent.page_url}` |
| Родитель родителя | `{parent.parent.name}` |
| Адрес страницы самого объекта | `{page_url}` |
| Ссылка родителя | `["parent:link:website", col: "url"]` |
| Профиль родителя на сайте | `["parent:profile:seascanner.com", col: "url"]` |
| Теги родителя из группы | `["parent:addressCountry"]` |

Правило одно: в **фигурных скобках** — `parent.` через точку (как `details.` у `{details.email}`), в **квадратных блоках** — префикс `parent:` внутри кавычек (как `link:` и `profile:`).

## Атрибуты и details — `{parent.…}`

```
{parent.name}                    имя родителя
{parent.short}                   любой публичный атрибут/метод родителя
{parent.details.year_founded}    detail родителя (по label.name), как {details.email} у самого объекта
{parent.page_url}                uri master-страницы родителя, например /msc-cruises
{parent.parent.name}             дедушка; parent. можно повторять, но не глубже 5 уровней
{page_url}                       uri страницы самого объекта (то же без parent.)
```

- Нет родителя (или он глубже 5 уровней) — подставится пустая строка.
- Нет такого атрибута у родителя — тоже пустая строка (ошибки не будет).
- `{parent}` без продолжения и `{parent_id}` работают как раньше: это обычные атрибуты самого объекта, не цепочка.

## Блоки — `["parent:…"]`

Префикс `parent:` ставится перед **любым полным блоком в кавычках** и меняет источник данных на родителя. Все опции блока работают как обычно: `col`, `limit`, `delimiter`, `before`, `after`, `before_tag`, `after_tag`, `if_empty`.

```
["parent:link:website", col: "url", before: "Сайт линии: "]
["parent:link:facebook", col: "url", if_empty: ""]
["parent:profile:seascanner.com", col: "url", before: "Профиль: ", if_empty: "нет профиля"]
["parent:profile:cruisecritic.com", col: "rating", before: "Рейтинг линии: "]
["parent:addressCountry", col: "slug"]
```

- Префикс можно повторить, чтобы подняться выше: `["parent:parent:link:website"]` — ссылка родителя родителя.
- Нет родителя — выводится `if_empty` (по умолчанию пусто, `before`/`after` не применяются).
- **Короткий синтаксис не работает.** `[parent.addressCountry]` — это группа тегов `parent` с полем `addressCountry`, а не родитель. Для родителя всегда полная запись в кавычках: `["parent:addressCountry"]`.

## Примеры

Данные: судно `MSC Seashore`, его родитель — линия `Msc Cruises`; у судна `details.passengers = 5877`, `details.year_of_build = 2021`.

**Заголовок и h1 судна**

```
title:  {name} — круизное судно линии {parent.name}
h1:     {name}
```

→ `MSC Seashore — круизное судно линии Msc Cruises`

**Тело страницы со ссылкой на страницу линии**

```
{name} — судно линии <a href="{parent.page_url}">{parent.name}</a>.
Построено в {details.year_of_build} году, вмещает {details.passengers} пассажиров.
["parent:link:website", col: "url", before: "Официальный сайт линии: ", if_empty: ""]
["parent:profile:seascanner.com", col: "url", before: "Профиль линии на SeaScanner: ", if_empty: ""]
```

→
```
MSC Seashore — судно линии <a href="/msc-cruises">Msc Cruises</a>.
Построено в 2021 году, вмещает 5877 пассажиров.
Официальный сайт линии: https://www.msccruises.com/int
Профиль линии на SeaScanner: https://www.seascanner.com/msc-cruises
```

Блок с `if_empty: ""`, который ничего не вывел, не оставляет пустых строк: рендерер схлопывает 3+ подряд идущих перевода строки до одного абзацного отступа.

**Свой адрес, чтобы не собирать его руками**

```
canonical: https://example.com{page_url}
```

**Цепочка родителей** (если когда-нибудь появится вложенность линия → бренд → судно)

```
{name}, {parent.name}, {parent.parent.name}
```

## Что нужно знать

**Порядок генерации.** `{parent.page_url}` берёт страницу родителя, которая существует *в момент рендера*, а текст сохраняется при генерации. Поэтому сначала генерируйте шаблон родителей (линии), потом потомков (суда). Если страницы родителя ещё не было, в тексте потомка будет пусто до следующей генерации с `force: true`. Если uri родителя потом изменится, старые ссылки спасут редиректы из `History`.

**Язык.** `page_url` — это uri master-страницы родителя (основной язык). Для переводов (`translate:pages`) в тексте остаётся тот же адрес.

**Опубликована ли страница.** `page_url` не проверяет `published`: при генерации страницы обычно ещё не опубликованы, и проверка навсегда выдала бы пусто. Следите за публикацией сами.

**List-шаблоны и Tag.** Для List-страниц (`template_type == "List"`) объект рендера — тег группы, и у `Tag` тоже есть `parent`: `{parent.name}` вернёт имя группы (например `Builder`). У `Tag` нет страницы, поэтому `{page_url}` для него пуст. Блоки с `parent:` не считаются «группой тегов» и не влияют на `referenced_group`/`referenced_groups` (по ним генератор группирует List-страницы).

**Нет eval.** Всё разбирается регулярками, код из шаблона не исполняется.

## Проверка на живых данных

```ruby
# bundle exec ruby -e '...' или в скрипте:
require './environment'

ship = Entity.find_by!(name: 'MSC Seashore')
render = ->(tpl) { TemplateFieldRenderer.new(ship).render(tpl) }

render.('{name} — судно линии {parent.name}')
render.('["parent:link:website", col: "url", before: "Сайт линии: "]')
render.('{parent.page_url}')   # пусто, пока у линии нет страницы
```

## Что рендерер умеет и без родителя (для контекста)

```
{name}                    атрибут самого объекта
{details.email}           detail самого объекта
[addressCountry]          теги из группы (короткий синтаксис), [addressCountry.slug] — с col
["addressCountry", col: "slug", limit: 2, delimiter: " / ", before: "(", after: ")", if_empty: ""]
["link:website", col: "url"]            ссылки объекта с label website
["profile:google.com", col: "rating"]   профиль объекта на сайте (domain или name)
```

Полное описание — в комментарии в начале `app/models/template_field_renderer.rb`.
