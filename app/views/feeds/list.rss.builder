require 'builder'
require 'time'

xml = Builder::XmlMarkup.new

xml.instruct! :xml, :version => "1.0"
xml.rss :version => "2.0" do
  xml.channel do
    xml.title       @page.h1.presence || @page.title
    xml.description @page.meta_description
    xml.link        "https://#{settings.domain}#{@page.uri}"

    @items.each do |item|
      xml.item do
        xml.title       item[:title]
        xml.description item[:summary]
        xml.link        item[:uri]
        xml.pubDate     item[:edited_at].rfc822
      end
    end
  end
end
