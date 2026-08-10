require 'builder'

# @pages = eval(@page.body)

xml = Builder::XmlMarkup.new

xml.instruct! :xml, :version => "1.0"
xml.rss :version => "2.0" do
  xml.channel do
    xml.title "#{settings.rss_feed_title[@lang]}"
    xml.description "#{settings.rss_feed_description[@lang]}"
    xml.link "https://#{settings.domain}"

    @pages.each do |page|
      xml.item do
        xml.title           page.title
        xml.description     page.meta_description
        xml.link            "https://#{settings.domain}#{page.uri}"
        xml.lastBuildDate   page.updated_at
      end
    end
  end
end