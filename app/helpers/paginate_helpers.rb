module PaginateHelpers

  def paginate(pages)
    if params[:q]
      search_params = "&" + params[:q].collect{|index, value| "q[#{index}]=#{value}"}.join('&') 
    end  


    @pages = pages
    
    abc = "<nav class='pagination is-right' role='navigation' aria-label='pagination'>"

    link_to_first =  "?page=#{pages.prev_page}"
    link_to_first = request.path_info if pages.prev_page == 1 
    abc += "<a class='pagination-previous' href='#{link_to_first}'>Previous</a>" if pages.prev_page 

    link_to_last =  "?page=#{pages.next_page}"
    abc += "<a class='pagination-previous' href='#{link_to_last}'>Next Page</a>" if pages.next_page 

    abc += "<ul class='pagination-list' style='list-style-type: none;'>"
    abc +=  "<li><a class='pagination-link #{'is-current' if 1 == @pages.current_page}' aria-label='Goto page 1' a href='#{request.path_info}?#{search_params}'>1</a></li>"

    (2..@pages.total_pages - 1).each do |page_n|
      if page_n == @pages.current_page - 2 || page_n == @pages.current_page + 2
        abc += "<li><span class='pagination-ellipsis'>&hellip;</span></li>"
      elsif [@pages.current_page - 1, @pages.current_page, @pages.current_page + 1].include?(page_n)
        abc += "<li><a class='pagination-link #{'is-current' if page_n == @pages.current_page}' aria-label='Goto page #{page_n}' href='?page=#{page_n}#{search_params}'>#{page_n}</a></li>"
      end 
    end 

    abc +=   "<li><a class='pagination-link #{'is-current' if @pages.total_pages == @pages.current_page}' aria-label='Goto page 86' a href='?page=#{@pages.total_pages}#{search_params}'>#{@pages.total_pages}</a></li>"
    abc +=  "</ul>"
    abc += "</nav>" 

    #abc += pagination_type

    abc = "" if pages.count == 0 #так проще обнулить??
    abc
  end

end