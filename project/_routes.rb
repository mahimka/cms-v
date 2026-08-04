class RoutesController < App
  
  #include AllMethodsController

  # def path_to_listing(item)
  #   item   
  # end 

  # def items_tags_by_parent
  #   items_tags_by_parent = []
  #   for item in @items
  #     items_tags_by_parent = items_tags_by_parent + item.tags
  #   end
  #   items_tags_by_parent.uniq!
  # end

  # before(%r{/(.+)/$}) { |path| redirect(path, 301) }

  # before "/*.xml" do
  #   if request.path_info.include?(".xml")
  #     request.path_info = request.path_info.gsub(".xml", "")
  #   end
  #   $is_xml = true
  #   redirect request.path_info.chomp("/")
  # end

  # IF_XML = false
  # before "/*" do
  #   if request.path_info.include?(".xml")
  #     IF_XML = true 
  #   else 
  #     IF_XML = false 
  #   end  
  # end


  before "/*/" do
    redirect request.path_info.chomp("/")
  end
 
  get "/sitemap.xml" do 
    @items = Item.all.last(10)
    builder :sitemap, layout: false
    #builder view.gsub('.builder', '').to_sym
  end

    # if (@page.url.include?(".rss") || @page.url.include?(".xml")) && (@page.active? || @auth.provided?)
    #   builder view.gsub('.builder', '').to_sym
    # elsif @page.active? || @auth.provided?
    #   erb view.gsub('.erb', '').to_sym, :layout => layout.gsub('.erb', '').to_sym
    # else
    #   pass
    #   # halt erb(:'default/views/error')  
    # end  

  # schema I ============================================= 

  get "/" do
    @countries = Ad.where(level: "country").joins(:items_of_country).where(items_of_country: { active: true }).uniq
    @adm1s     = Ad.where(level: "adm1")   .joins(:items_of_adm1)   .where(items_of_adm1: { active: true }).uniq
    @adm2s     = Ad.where(level: "adm2")   .joins(:items_of_adm2)   .where(items_of_adm2: { active: true }).uniq
    @pps       = Ad.where(level: "pp")     .joins(:items_of_pp)     .where(items_of_pp: { active: true }).uniq
     
    @home_country = Ad.where(level: "country", name_short: "United States").first

    @countries = Ad.where(level: "country")

    @items = Item.active.order(apdated_at: :desc) 
    @items = @items.page(params[:page]).per(settings.per_page)

    @title = "Yogamela.com - find yoga classes near me"
    erb :home, :layout => :"/layout/layout"
  end
  
  # /listings /reviews /profiles etc
  get "#{settings.items_folder}" do 

    @q = Item.active.ransack(params[:q])
    @items_found = @q.result(distinct: true) # for index.rb
    @items = @q.result(distinct: true).page(params[:page]).per(settings.per_page)

    @title = "All Yoga Classes listed at Yogamela.com"

    erb :items, :layout => :"/layout/layout"
  end  

  get "#{settings.items_folder}/:permalink" do 

    # return "Hello"
    # @item = Item.find(params[:id])
    @item = Item.find_by_permalink(params[:permalink])

    pass unless @item
     
    @ad = @item.pp 

    @country = @item.country
    @adm1    = @item.adm1 
    @adm2    = @item.adm2 
    @pp      = @item.pp  

    @title = "#{@item.name ? @item.name : ''} - #{@item.pp ? @item.pp.name : ''}, #{@item.adm1 ? @item.adm1.name : ''}, #{@item.country ? @item.country.name : ''} "  + " - Yogamela.com"

    erb :item, :layout => :"/layout/layout"
  end

  #get "/tags" do  
  get "#{settings.tags_folder}" do   
    @tags = Tag.all
    @parenttags = Tag.parenttags

    @title = "Directory of Yoga Style and Classes Types - Yogamela.com "

    erb :tags, :layout => :"/layout/layout"
    # erb :display_parent_tag
  end   

  get "/:ad/:tag" do 

    @ad   = Ad.find_by_permalink(params[:ad])
    @tag  = Tag.find_by_permalink(params[:tag])

    pass if @ad.nil? || @tag.nil?

    @country = @ad.country 

    # @state   = @ad.find_state 
    # @state   = @ad if @ad.level == "state"
    # @pp    = @ad if @ad.level == "pp" 

    if @ad.country?

      @country = @ad
      
      @items = @ad.items_of_country.active
      @items_tags_by_parent = items_tags_by_parent
      @title = @tag.name + " - " + @items.size.to_s + " classes in " + @ad.name + " - Yogamela.com"
      @items = @items.page(params[:page]).per(settings.per_page)

      erb :country_tag, :layout => :"/layout/layout" 
    
    elsif @ad.adm1?

      @adm1 = @ad
    
      @items = @ad.items_of_adm1.active
      @items_tags_by_parent = items_tags_by_parent
      @title = @tag.name + " - " + @items.size.to_s + " classes in " + @ad.name + ", " + @country.name + " - Yogamela.com"
      @items = @items.page(params[:page]).per(settings.per_page)

      erb :adm1_tag, :layout => :"/layout/layout"  

    elsif @ad.adm2?

      @adm2 = @ad
      @adm1 = @ad.adm1
    
      @items = @ad.items_of_adm2.active
      @items_tags_by_parent = items_tags_by_parent
      @title = @tag.name + " - " + @items.size.to_s + " classes in " + @ad.name + ", " + @country.name + " - Yogamela.com"
      @items = @items.page(params[:page]).per(settings.per_page)

      erb :adm2_tag, :layout => :"/layout/layout"

    
    elsif @ad.pp?

      @pp = @ad
      @adm2 = @ad.adm2
      @adm1 = @ad.adm1

      @items = @ad.items_of_pp.active
      @items_tags_by_parent = items_tags_by_parent
      @title = @tag.name + " - " + @items.size.to_s + " classes in " + @ad.name + ", " + ", " + @country.name + " - Yogamela.com"
      @items = @items.page(params[:page]).per(settings.per_page)

      erb :pp_tag, :layout => :"/layout/layout"
    
    end

  end 

  get "/:ad" do 

    @ad = Ad.find_by_permalink(params[:ad])
    
    pass if @ad.nil? 

    @country = @ad.country #if @ad.country? 
    # @adm1    = @ad.adm1 
    # @adm2    = @ad.adm2
    # @pp      = @ad.pp     


    if @ad.country?

      @country = @ad
      
      @items = @ad.items_of_country.active
      @items_tags_by_parent = items_tags_by_parent
      @adm1s_of_country = @ad.children.collect{|ad| ad if ad.items_of_adm1.active.size > 0 }.compact.uniq

      @title = @items.size.to_s + " Yoga Classes in " + @ad.name
      @items = @items.page(params[:page]).per(settings.per_page)

      erb :country, :layout => :"/layout/layout" 

    elsif @ad.adm1?

      @adm1 = @ad

      @items = @ad.items_of_adm1.active
      @items_tags_by_parent = items_tags_by_parent
      
      @adm2s_of_adm1 = @ad.children.collect{|ad| ad if ad.items_of_adm2.active.size > 0 }.compact.uniq
      @pps_of_adm1 = @ad.children.collect{|ad| ad if ad.items_of_pp.active.size > 0 }.compact.uniq

      @title = @items.size.to_s + " Yoga Classes in " + @ad.name + ", " + @country.name + " - Yogamela.com"
      @items = @items.page(params[:page]).per(settings.per_page)
      
      erb :adm1, :layout => :"/layout/layout"  


    elsif @ad.adm2?

      @adm2 = @ad
      @adm1 = @ad.adm1

      @items = @ad.items_of_adm1.active
      @items_tags_by_parent = items_tags_by_parent
      @pps_of_adm2 = @ad.children.collect{|ad| ad if ad.items_of_pp.active.size > 0 }.compact.uniq

      @title = @items.size.to_s + " Yoga Classes in " + @ad.name + ", " + @country.name + " - Yogamela.com"
      @items = @items.page(params[:page]).per(settings.per_page)
      
      erb :adm2, :layout => :"/layout/layout"  

    elsif @ad.pp?
      @pp = @ad
      @adm2 = @ad.adm2
      @adm1 = @ad.adm1     
      
      @items = @ad.items_of_pp #.active
      @items_tags_by_parent = items_tags_by_parent

      @title = @items.size.to_s + " Yoga Classes in " + @ad.name + ", " + @adm1.name + @country.name_short + " - Yogamela.com"
      # @title = @items.size.to_s + " Yoga Classes in " + @ad.name + ", " + @adm1.name + ", " + @country.name
      @items = @items.page(params[:page]).per(settings.per_page)

      erb :pp, :layout => :"/layout/layout"
    end


  end      

  # get "#{settings.tags_folder}/:tag" do 
  get "/:tag" do 
    @tag = Tag.find_by_permalink(params[:tag])

    pass if @tag.nil? 

    # puts @tag.content.title

    if @tag.parent_id
      
      @items = @tag.items.active

      #@countries = @tag.items.active.map{|item| item.country }.uniq.compact

      @countries = h_countries_of_items(@tag.items.active)
      @adm1s = h_adm1s_of_items(@tag.items.active, "United States", 6252001)
      @adm2s = h_adm2s_of_items(@tag.items.active, "United States", 6252001)
      @pps = h_pps_of_items(@tag.items.active, "United States", 6252001) 

      # @us_states = @tag.items.active.map{|item| item.state if item.state.find_country.name == "United States" }.uniq.compact
      # @us_cities = @tag.items.active.map{|item| item.pp if !item.pp.nil? && item.country.name == "United States" }.uniq.compact

      @title = @items.size.to_s + " " + (@tag.content.title || @tag.name) + " Classes Worldwide - Yogamela.com"
      @meta_description = @tag.content.meta_description
      @items = @items.page(params[:page]).per(settings.per_page)

      erb :tag, :layout => :"/layout/layout"
    
    else

      @parent_tag = @tag

      @title = !@parent_tag.content.title.blank? ?  @parent_tag.content.title.blank? : @parent_tag.name +  " - Yogamela.com"
      @meta_description = @parent_tag.content.meta_description


      erb :parent_tag, :layout => :"/layout/layout"

    end
  end


  get "*" do 
    history = History.where(lost_url: params['splat']).first

    history = History.find_or_create_by(lost_url: params['splat'], new_url: "/", url_type: "other") unless history

    new_destination = history&.new_url
    code = history&.permanent == true ? 301 : 302

    redirect new_destination, code
  end



  # # schema II ============================================= 

  # get "/:country" do 
  #   @country = Ad.find_by_permalink(params[:country])

  #   pass if @country.nil? 
  #   erb :ad
  #   # erb :country
  # end   

  # get "/:country/:state" do 
  #   @country = Ad.find_by_permalink(params[:country])
  #   @state = Ad.find_by_permalink(params[:state])

  #   pass if @country.nil? || @state.nil?
  #   erb :ad
  #   # erb :state
  # end  

  # get "/:country/:state/:pp" do 
  #   @country = Ad.find_by_permalink(params[:country])
  #   @state = Ad.find_by_permalink(params[:state])
  #   @pp = Ad.find_by_permalink(params[:pp])

  #   pass if @country.nil? || @state.nil? || @pp.nil?
  #   erb :ad
  #   # erb :pp    
  # end    

  # get "/listings" do 
  #   @item = Item.all
  #   erb :listings
  # end  

  # get "/listings/:id" do 
  #   @item = Item.find(params[:id])
  #   erb :listing
  # end

  # get "/tags" do 
  #   @tags = Tag.all
  #   erb :tags 
  #   # erb :display_parent_tag
  # end   

  # get "/:ad/:tag" do 
  #   @ad   = Ad.find_by_permalink(params[:ad])
  #   @tag  = Tag.find_by_permalink(params[:tag])

  #   pass if @ad.nil? || @tag.nil?

  #   @country = @ad.find_country 
  #   @ad1     = @ad.find_ad1 

  #   erb :ad_tag
  # end 

  # # get "/tags/:tag" do 
  # get "/:tag" do 
  #   @tag = Tag.find_by_permalink(params[:tag])

  #   # halt 404 if @tag.nil? 

  #   erb :tag 
  #   # erb :parent_tag
  # end

end