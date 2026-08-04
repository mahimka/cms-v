class FetchProfiles

  require 'ferrum'
  
  def initialize(site, profileable_type) # profileable_type = Affprogram or Operator

    @site = site
    @profileable_type = profileable_type

    # @timeout = 15
    # @headless = true
    # @sleep_time = 2

    @urls = []
    @report = {site_domain: @site.domain,
      profileable_type: @profileable_type 
    }

    # http://www.railstips.org/blog/archives/2009/05/15/include-vs-extend-in-ruby/
    # include provides instance methods for the class that mixes it in.
    # extend provides class methods for the class that mixes it in.
    require "./parsers/sources/#{@site.domain}.rb" 
    # puts "#{@site.domain.gsub(/\.|-/, '_')}".camelize.constantize 
    extend "#{@site.domain.gsub(/\.|-/, '_')}".camelize.constantize # as class methods!!

  end

  def get_profile_urls 

    # domain.com.rb module
    timeout = settings_fetch_profiles[:timeout]    
    headless = settings_fetch_profiles[:headless]
    sleep_time = settings_fetch_profiles[:sleep_time]
    sleep_retry = settings_fetch_profiles[:retry]
     
    puts @site.domain
    puts "here"
    puts "#{@profileable_type.downcase}_index_urls"

    self.send("#{@profileable_type.downcase}_index_urls").each do |index_url| # domain.com.rb module 

      begin

        @browser = Ferrum::Browser.new(timeout: timeout, headless: headless)
        @browser.goto(index_url)
        puts index_url
        self.send("#{@profileable_type.downcase}_parse_urls", @browser) # domain.com.rb module
        
        sleep(rand(sleep_time)) if defined?(self.sleep_time)

      rescue Ferrum::TimeoutError => e

        puts "Exception Class: #{ e.class.name }"
        puts "Ferrum::TimeoutError: #{ e.message }"
        # puts "Ferrum::TimeoutError: #{ e.backtrace }"   

        timeout += 5
        puts "timeout is set to: " + timeout.to_s
        retry  
    
      rescue Ferrum::PendingConnectionsError => e

        puts "Exception Class: #{ e.class.name }"
        puts "Ferrum::PendingConnectionsError: #{ e.message }"
        # puts "Ferrum::PendingConnectionsError: #{ e.backtrace }"   

        timeout += 5
        puts "timeout is set to: " + timeout.to_s
        retry

      rescue Ferrum::NodeNotFoundError => e
        puts "Exception Class: #{ e.class.name }"
        puts "Ferrum::NodeNotFoundError: #{ e.message }"
        # puts "Ferrum::NodeNotFoundError: #{ e.backtrace }"        
        sleep (rand(sleep_retry))
        retry
        
      rescue Exception => e # all other errors

        # puts "Got an exception, but I'm responding intelligently!"
        puts "Exception Class: #{ e.class.name }"
        puts "Exception Message: #{ e.message }"
        # puts "Exception Backtrace: #{ e.backtrace }"   

      end

      @browser.quit

      puts @urls.inspect

      save_to_baza
      @urls = []
      puts
      puts

    end
 
    # @browser.quit


    puts "@urls.size: " + @urls.size.to_s
    @urls.uniq!

  end

  def save_to_baza  #(urls)

    @report[:urls_size] = @urls.size
    @report[:profiles_count_before] = @site.profiles.where(profileable_type: @profileable_type).size
    report[:saved_profiles_count] = 0

    @urls.each do |url| 
      profile = Profile.find_or_initialize_by(url: url) # site_id: @site.id, profileable_type: @profileable_type

      if profile.new_record?
        profile.site_id = @site.id
        profile.profileable_type = @profileable_type

        if profile.save!
          print 'N'.red
          @report[:saved_profiles_count] += 1 
        end
      else
        print '.'
      end
    end

    @report[:profiles_count_after] = @site.profiles.where(profileable_type: @profileable_type).size
    # @report[:new_profiles_count] = report[:saved_profiles_count] - report[:profiles_count_before]

    # what to return???????????????
    report
  end

  def report # param for returning report in different formats??
    @report
  end

  def urls # param for returning report in different formats??
    @urls
  end

  # def temp_find_dif
  #   dif = @site.profiles.where(profileable_type: @profileable_type).collect{|profile| profile.name} - urls
  #   # puts dif
  # end

end