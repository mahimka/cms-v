class ParseProfile

  require 'ferrum'

  # нужны ли эти, или достаточно affprogram_name, affprogram_domain etc???
  attr_reader :name, :domain, :scores, :badges, :links, :contacts, :labels, :mixed, :report

  # двинуть @browser to initialize?????????????????????????
  
  def initialize(profile) # profileable_type profileable_type = Affprogram or Operator

    @profile = profile
    @profileable_type = @profile.profileable_type
    @site = profile.site

    @name     = ''
    @domain   = ''
    @scores   = {value_admin: nil, value_users: nil} # must be preset?  value_badges: nil
    @badges   = {positive: nil, negative: nil, closed: nil} 
    @links    = {} # must be preset?
    @contacts = {} # must be preset?
    @labels   = {}
    @mixed    = {} 

    @report = {}

    require "./parsers/sources/#{@site.domain}.rb" 
    # puts "#{@site.domain.gsub(/\.|-/, '_')}".camelize.constantize 
    extend "#{@site.domain.gsub(/\.|-/, '_')}".camelize.constantize # as class methods!!

    @browser = browser

  end


  # def affprogram_domain 
  #   @domain = "set method in module site.com.rb"
  # end 


  # common methods -------------------------------------------

  def browser

    # domain.com.rb module
    @timeout = settings_parse_profile[:timeout]    
    headless = settings_parse_profile[:headless]
    sleep_time = settings_parse_profile[:sleep_time]
    sleep_retry = settings_parse_profile[:retry]

    puts @site.domain
    puts @profile.name

    begin

      @browser = Ferrum::Browser.new(timeout: @timeout, headless: headless)
      @browser.goto(@profile.name)

    rescue Ferrum::TimeoutError => e

      puts "Exception Class: #{ e.class.name }"
      puts "Ferrum::TimeoutError: #{ e.message }"
      # puts "Ferrum::TimeoutError: #{ e.backtrace }"   

      @timeout += 10
      puts "timeout is set to: " + @timeout.to_s
      retry  
  
    rescue Ferrum::PendingConnectionsError => e

      puts "Exception Class: #{ e.class.name }"
      puts "Ferrum::PendingConnectionsError: #{ e.message }"
      # puts "Ferrum::PendingConnectionsError: #{ e.backtrace }"   

      @timeout += 10
      puts "timeout is set to: " + @timeout.to_s
      sleep (rand(sleep_retry))
      retry

    rescue Ferrum::NodeNotFoundError => e

      puts "Exception Class: #{ e.class.name }"
      puts "Ferrum::NodeNotFoundError: #{ e.message }"
      # puts "Ferrum::NodeNotFoundError: #{ e.backtrace }"        
      sleep (rand(sleep_retry))
      retry
      
    rescue Exception => e # all other errors

      puts "Exception Class: #{ e.class.name }"
      puts "Exception Message: #{ e.message }"
      puts "Exception Backtrace: #{ e.backtrace }"   

    end

    @browser

  end

  def browser_quit
    @browser.quit
  end

  def body
    @browser.body
  end

  def nokogiri_doc
    Nokogiri::HTML(@browser.body)
  end

  def parse_affprogram_all 
    affprogram_name
    affprogram_domain
    affprogram_scores
    affprogram_badges
    affprogram_links
    affprogram_contacts
    affprogram_labels
    affprogram_mixed

    save_to_specific 
    create_labels_from_profile_badges
    create_labels_from_profile_labels
  end

  def parse_operator_all 
    operator_name
    operator_domain
    operator_scores
    operator_badges
    operator_links
    operator_contacts
    operator_labels
    operator_mixed

    save_to_specific 
    create_labels_from_profile_badges
    create_labels_from_profile_labels
  end

  # def parse_affprogram_scores_and_badges 
  #   affprogram_scores
  #   affprogram_badges

  #   save_to_specific
  #   create_labels_from_profile_badges
  #   create_labels_from_profile_labels
    # browser_quit
  # end

  def parse_selected(*args)
    args.each do |arg|
      # puts arg
      send(arg)
    end

    save_to_specific
    create_labels_from_profile_badges
    create_labels_from_profile_labels
    browser_quit
  end


  # now in CalculateRating
  # def save_to_scores

  #   score = Score.where(profile_id: @profile.id).create
  #   score.value_admin = @scores[:value_admin]
  #   score.value_users = @scores[:value_users]
  #   # score.tag_id      = @scores[:value_users]

  #   score.save

  # end


  def save_to_specific

    specific = Specific.where(profile_id: @profile.id, :site_id => @profile.site_id).first_or_create
    specific.name     = @name unless @name.nil? || @name.blank?
    specific.domain   = @domain unless @domain.nil? || @domain.blank?
    specific.scores   = @scores unless @scores.nil? || @scores.blank?
    specific.badges   = @badges unless @badges.nil? || @badges.blank?
    specific.labels   = @labels unless @labels.nil? || @labels.blank?
    specific.links    = @links unless @links.nil? || @links.blank?
    specific.contacts = @contacts unless @contacts.nil? || @contacts.blank?
    specific.mixed    = @mixed unless @mixed.nil? || @mixed.blank?
    specific.save

    @profile.response = @browser.network.status
    @profile.checked_at = DateTime.now 
    @profile.save 

  end


  def create_labels_from_profile_badges

    badges.each do |k, v|
      if v && !v.blank?

        if v.kind_of?(Array)
          v.each do |label_name|
            # puts "- " + label_name.length.to_s + " - " + label_name
            label = Marker.where(:group => "Badges", :name => label_name[0..240], :site_id => @profile.site_id).first_or_create
            ProfileMarker.where(:marker_id => label.id, :profile_id => @profile.id).first_or_create
          end
        elsif v.kind_of?(String)
          # puts k + " - " + v
          label = Marker.where(:group => "Badges", :name => v[0..240], :site_id => @profile.site_id).first_or_create
          ProfileMarker.where(:marker_id => label.id, :profile_id => @profile.id).first_or_create
        end
      end
    end  

  end
  
  def create_labels_from_profile_labels

    labels.each do |k, v|
      puts k 
      if v && !v.blank?
        v.each do |label_name|
          # puts "- " + label_name.length.to_s + " - " + label_name
          label = Marker.where(:group => k, :name => label_name[0..240], :site_id => @profile.site_id).first_or_create
          # puts "label created:" + label.name
          ProfileMarker.where(:marker_id => label.id, :profile_id => @profile.id).first_or_create
          # puts "labeling created"
        end
      end  
    end  
  end


end