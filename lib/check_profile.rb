class CheckProfile

  @@report = {checked_count: 0, set_404_count: 0, set_redirect_count: 0}	

  def initialize(profile)
    @profile = profile
    @browser = browser

    @@report[:checked_count] += 1
  end

  def report 
    @@report
  end

  def request_hash 
    @request_hash = JSON.parse(@browser.network.request.to_json)
  end

  # def response_hash 
  #   @response_hash = @browser.network.response.inspect
  # end  

  # if site redirects to another page with final code 200, the only way to know it:
  def redirected?
  	true if request_hash["params"]["documentURL"] != @profile.name
    # request_hash["params"]["redirectHasExtraInfo"] == true
  end

  def status   	
  	if redirected?
      301
    else
      @browser.network.status
    end
  end

  def response_url
    request_hash["params"]["documentURL"]
  end

  def new_profile_exists?
  	if redirected?
      @new_profile = Profile.find_by_name(response_url)
    end
  end

  # problems witn 403 https://www.casinomeister.com/casino-reviews/crazy-vegas/
  # def manage_4xx
  def manage_404
    
  	# if status.to_s.match(/^4\d\d$/)
  	if status.to_s == "404"
	  @profile.active = false
	  @profile.response = status
	  @profile.checked_at = DateTime.now 

	  begin
        @@report[:set_404_count] += 1 if @profile.save
      rescue Exception => e
        puts "Exception Class: #{ e.class.name }"
        puts "Ferrum::TimeoutError: #{ e.message }"
        # puts "Ferrum::TimeoutError: #{ e.backtrace }"  
        sleep(2)
        retry
      end	

  	end
  end

  def manage_redirect
  	if redirected?

      @profile.active = false
	  @profile.response = status
	  @profile.checked_at = DateTime.now 

	  if new_profile_exists?

	    print "  - redirects to existing profile: " + @new_profile.name  
        @profile.new_id = @new_profile.id
        @profile.redirects_to = nil

      else
        @profile.new_id = nil
        print "  - redirects to new url: "  + response_url
        @profile.redirects_to = response_url
      end

	  begin
        @@report[:set_redirect_count] += 1 if @profile.save
      rescue Exception => e
        puts "Exception Class: #{ e.class.name }"
        puts "Ferrum::TimeoutError: #{ e.message }"
        # puts "Ferrum::TimeoutError: #{ e.backtrace }"  
        sleep(2)
        retry
      end	      

    else
      puts " -- not redirected!!!"
    end

  end


  def browser

    timeout = 5   
    headless = true
    headless = false if [22].include?(@profile.site_id) # 22 - Askgablers 
    sleep_retry = 3

    # puts @site.domain
    # puts @profile.name

    begin

      browser = Ferrum::Browser.new(timeout: timeout, headless: headless)
      # browser.goto('https://www.casinomeister.com/casino-reviews/golden-lounge/trstrstrstrs')
      browser.goto(@profile.name)

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
      sleep (rand(sleep_retry))
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
      puts "Exception Backtrace: #{ e.backtrace }"   
      sleep (rand(sleep_retry))
      retry

    end

    @browser = browser.dup
    browser.quit
    return @browser

  end


end