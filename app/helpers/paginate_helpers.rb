module PaginateHelpers

  # base_path — если задан, ссылки строятся как base_path/N (страница 1 —
  # просто base_path, без /1) вместо ?page=N — так публичные списковые
  # страницы (_list_paginated) получают чистый /argentina/2 вместо
  # /argentina?page=2. Админские index-страницы (ransack q[...], поиск
  # живёт в query-string, path там не подходит) base_path не передают —
  # для них поведение не изменилось.
  def paginate(pages, base_path: nil)
    if params[:q]
      search_params = "&" + params[:q].collect{|index, value| "q[#{index}]=#{value}"}.join('&')
    end


    @pages = pages

    page_href = lambda do |n|
      if base_path
        n == 1 ? base_path : "#{base_path}/#{n}"
      else
        n == 1 ? "#{request.path_info}?#{search_params}" : "?page=#{n}#{search_params}"
      end
    end

    abc = "<nav class='pagination is-right' role='navigation' aria-label='pagination'>"

    abc += "<a class='pagination-previous has-background-link-light' href='#{page_href.call(pages.prev_page)}'>Previous</a>" if pages.prev_page

    abc += "<a class='pagination-previous has-background-link-light' href='#{page_href.call(pages.next_page)}'>Next Page</a>" if pages.next_page

    abc += "<ul class='pagination-list' style='list-style-type: none;'>"
    abc +=  "<li><a class='has-background-link-light pagination-link #{'is-current' if 1 == @pages.current_page}' aria-label='Goto page 1' a href='#{page_href.call(1)}'>1</a></li>"

    (2..@pages.total_pages - 1).each do |page_n|
      if page_n == @pages.current_page - 2 || page_n == @pages.current_page + 2
        abc += "<li><span class='pagination-ellipsis'>&hellip;</span></li>"
      elsif [@pages.current_page - 1, @pages.current_page, @pages.current_page + 1].include?(page_n)
        abc += "<li><a class='pagination-link #{'is-current' if page_n == @pages.current_page}' aria-label='Goto page #{page_n}' href='#{page_href.call(page_n)}'>#{page_n}</a></li>"
      end
    end

    abc +=   "<li><a class='pagination-link #{'is-current' if @pages.total_pages == @pages.current_page}' aria-label='Goto page 86' a href='#{page_href.call(@pages.total_pages)}'>#{@pages.total_pages}</a></li>"
    abc +=  "</ul>"
    abc += "</nav>"

    #abc += pagination_type

    abc = "" if pages.count == 0 #так проще обнулить??
    abc
  end

end