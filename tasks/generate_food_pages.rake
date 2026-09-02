# Портовые (koper/piran/portoroz) страницы /eateries под соответствующим
# городом — по аналогии с уже существующей /izola/eateries — и
# генерация draft-страниц (ready:false, published:false) для Entity со
# schema FoodEstablishment, у которых ещё нет page. Текст (subtitle/
# meta_description/body/характеристика) пишет DeepSeek по уже собранным
# тегам/деталям сущности (без обращения к внешнему поиску — see
# lib/deepseek_client.rb#generate_page_copy).
namespace :entities do
  namespace :food_pages do
    # Тег addressLocality "Portoroz" (ASCII, как в URL /portoroz/...) — а
    # для текста/заголовков нужна словенская форма с диакритикой.
    CITY_DISPLAY_NAMES = { 'Portoroz' => 'Portorož' }.freeze

    CITY_EATERIES_CONTENT = {
      'Koper' => {
        title: 'Hrana in pijača v Kopru: restavracije, gostilne in vinske kleti',
        h1: 'Hrana in pijača v Kopru',
        subtitle: 'Odkrijte najboljše restavracije, konobe, kavarne in vinske kleti v Kopru.',
        meta_description: 'Vodnik po kulinarični ponudbi Kopra. Poiščite najboljše gostilne, sveže morske sadeže, lokalna vina in prijetne lokale v starem mestnem jedru.'
      },
      'Piran' => {
        title: 'Hrana in pijača v Piranu: restavracije, gostilne in vinske kleti',
        h1: 'Hrana in pijača v Piranu',
        subtitle: 'Odkrijte najboljše ribje restavracije, konobe in vinske kleti v romantičnem Piranu.',
        meta_description: 'Vodnik po kulinarični ponudbi Pirana. Poiščite najboljše gostilne, sveže morske sadeže in prijetne lokale ob obali.'
      },
      'Portoroz' => {
        title: 'Hrana in pijača v Portorožu: restavracije, gostilne in vinske kleti',
        h1: 'Hrana in pijača v Portorožu',
        subtitle: 'Odkrijte najboljše restavracije, plažne bare in vinske kleti v Portorožu.',
        meta_description: 'Vodnik po kulinarični ponudbi Portoroža. Poiščite najboljše restavracije, sveže morske sadeže in prijetne lokale ob glavni promenadi.'
      }
    }.freeze

    TAG_GROUPS_FOR_CONTEXT = %w[
      cuisines dishes drinks desserts restaurant_features
      meal_type good_for payment_options price_range restrictions
    ].freeze

    desc "Создать /{city}/eateries для Koper/Piran/Portoroz по образцу /izola/eateries, если их ещё нет (rake entities:food_pages:ensure_city_indexes)"
    task :ensure_city_indexes do
      CITY_EATERIES_CONTENT.each do |tag_name, content|
        city_page = Page.find_by(uri: "/#{tag_name.downcase}", master_id: nil)

        unless city_page
          puts "#{tag_name}: пропуск — нет страницы города /#{tag_name.downcase}"
          next
        end

        if city_page.children.exists?(slug: 'eateries')
          puts "#{tag_name}: уже есть /#{tag_name.downcase}/eateries"
          next
        end

        page = Page.new(
          parent_id: city_page.id,
          lang: 'sl',
          slug: 'eateries',
          view: 'default_index.erb',
          layout: 'default.erb',
          title: content[:title],
          h1: content[:h1],
          subtitle: content[:subtitle],
          meta_description: content[:meta_description],
          anchor_1: 'Hrana in pijača',
          anchor_2: content[:h1],
          conditions: { 'object' => 'Entity', 'tags' => ['and', tag_name, 'FoodEstablishment'] },
          ready: true,
          published: true
        )

        if page.save
          puts "#{tag_name}: создано #{page.uri}"
        else
          puts "#{tag_name}: ОШИБКА — #{page.errors.full_messages.join(', ')}"
        end
      end
    end

    desc "Создать draft-страницы (ready:false, published:false) для Entity со schema FoodEstablishment без page (rake entities:food_pages:create[limit])"
    task :create, [:limit] do |_, args|
      client = DeepseekClient.new(api_key: App.settings.api_deepSeek_v3_1)

      food_schema = Schema.find_by!(name: 'FoodEstablishment')
      entities = Entity.where(schema_id: food_schema.id)
      with_page_ids = Page.where(pageable_type: 'Entity', pageable_id: entities.select(:id)).pluck(:pageable_id)
      pending = entities.where.not(id: with_page_ids).order(:id)
      pending = pending.limit(args[:limit].to_i) if args[:limit].present?

      puts "К созданию: #{pending.count}"

      created = 0
      skipped = 0

      pending.each do |entity|
        locality_tag = entity.first_tag_of_group('addressLocality')

        if locality_tag.blank?
          puts "##{entity.id} #{entity.name}: пропуск — нет тега addressLocality"
          skipped += 1
          next
        end

        eateries_page = Page.find_by(uri: "/#{locality_tag.downcase}/eateries", master_id: nil)

        if eateries_page.nil?
          puts "##{entity.id} #{entity.name}: пропуск — нет страницы /#{locality_tag.downcase}/eateries"
          skipped += 1
          next
        end

        # Один и тот же name (сеть с несколькими точками, напр. "Pizza 33")
        # может встретиться в одном городе дважды — дописываем id entity,
        # а не пропускаем: это реально разные заведения, а не дубль импорта.
        base_slug = SlugGenerator.call(entity.name)
        slug = eateries_page.children.exists?(slug: base_slug) ? "#{base_slug}-#{entity.id}" : base_slug

        locality_display = CITY_DISPLAY_NAMES[locality_tag] || locality_tag
        context = build_food_page_context(entity, locality_display)

        begin
          copy = client.generate_page_copy(context)
        rescue => e
          puts "##{entity.id} #{entity.name}: ОШИБКА генерации — #{e.class}: #{e.message}"
          skipped += 1
          next
        end

        page = Page.new(
          parent_id: eateries_page.id,
          lang: 'sl',
          slug: slug,
          view: 'profile_restaurant.erb',
          layout: 'default.erb',
          pageable_type: 'Entity',
          pageable_id: entity.id,
          title: "#{entity.name} - #{copy['characteristic']} - #{locality_display}",
          h1: entity.name,
          subtitle: copy['subtitle'],
          anchor_1: entity.name,
          anchor_2: "#{entity.name} - #{locality_display}",
          meta_description: copy['meta_description'],
          body: copy['body'],
          ready: false,
          published: false
        )

        if page.save
          created += 1
          puts "##{entity.id} #{entity.name}: OK -> #{page.uri}"
        else
          skipped += 1
          puts "##{entity.id} #{entity.name}: ОШИБКА сохранения — #{page.errors.full_messages.join(', ')}"
        end
      end

      puts "Готово: создано #{created}, пропущено #{skipped}"
    end
  end
end

def build_food_page_context(entity, locality_display)
  lines = ["Ime: #{entity.name}", "Mesto: #{locality_display}"]
  lines << "Naslov: #{entity.address}" if entity.address.present?

  profile = entity.profiles.where.not(rating: nil).first
  lines << "Ocena: #{profile.rating} (#{profile.review_count || 0} ocen)" if profile

  TAG_GROUPS_FOR_CONTEXT.each do |group|
    values = entity.tags_of_group_localized(group, 'sl')
    next if values.empty?

    lines << "#{group}: #{values.join(', ')}"
  end

  lines.join("\n")
end
