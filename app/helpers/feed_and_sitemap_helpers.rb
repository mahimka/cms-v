module FeedAndSitemapHelpers

	# Данные для sitemap.xml/sitemaps/index.xml.builder: опубликованные
	# страницы указанного языка, с картинками их pageable (Entity/Item/Event)
	# для image sitemap extension. lang уже фильтрует @pages, поэтому
	# page.h1 и picture.translation(lang) сразу берутся в нужном языке.
	def sitemap_pages(lang)
	  Page.published.where(lang: lang).map do |page|
	    {
	      uri:        "https://#{settings.domain}#{page.uri}",
	      updated_at: page.updated_at,
	      title:      page.h1,
	      pictures:   sitemap_pictures(page, lang)
	    }
	  end
	end

	def sitemap_pictures(page, lang)
	  pageable = page.pageable

	  return [] unless pageable.respond_to?(:pictures)

	  pageable.pictures.published.active.order(:position).map do |picture|
	    {
	      loc:     "https://#{settings.domain}#{picture.file}",
	      caption: picture.translation(lang)
	    }
	  end
	end

	# Пункты .rss для списковой страницы (Page с conditions, например /beaches):
	# по каждому объекту из list_objects берём его СОБСТВЕННУЮ детальную
	# страницу на языке списковой страницы и её edited_at — дата проставляется
	# вручную в форме при серьёзных изменениях, а не automatic updated_at,
	# который дёргается от любого технического сохранения записи.
	# Объекты без страницы на этом языке или без edited_at в фид не попадают.
	def feed_items_for_list_page(page)
	  page.list_objects
	    .select { |object| object.respond_to?(:page) }
	    .filter_map do |object|
	      item_page = object.page&.version_for(page.lang)

	      next if item_page.nil? || !item_page.published? || item_page.edited_at.nil?

	      {
	        title:     item_page.h1.presence || item_page.title,
	        summary:   item_page.meta_description,
	        uri:       "https://#{settings.domain}#{item_page.uri}",
	        edited_at: item_page.edited_at
	      }
	    end
	    .sort_by { |item| -item[:edited_at].to_i }
	    .first(30)
	end

end