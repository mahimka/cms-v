class RoutesController < App

    get '/test-routes' do
      # erb :"/index", layout: :"/layout/layout" #, views: settings.views_default   

    end

    get '*' do |uri|
       @page = Page.where(uri: uri).first

       halt 404, "Not Found\n" unless @page

       call_erb_view(@page.view, layout: @page.layout)

    end


    # get '/products' do
    #   # call_erb_view("index")
    #   # erb :"/index", layout: :"/layout/layout" #, views: settings.views_default

    #   @page = Page.where(uri: '/products').first

    #   @page.title

    #   page_view = 'index'

    #   call_erb_view(page_view)
    # end


    # get '/products/:uri' do
    #   # call_erb_view("index")
    #   # erb :"/index", layout: :"/layout/layout" #, views: settings.views_default

    #   @page = Page.where(uri: '/products/' + params[:ean]).first

    #   @page.title

    #   call_erb_view(@page.view.sub('.erb', ''))
    # end
    


end  