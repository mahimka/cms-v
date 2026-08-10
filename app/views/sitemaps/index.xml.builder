require 'builder'

xml = Builder::XmlMarkup.new

xml.instruct! :xml, :version => "1.0", :encoding => "UTF-8"

xml.urlset(
  "xmlns"       => "http://www.sitemaps.org/schemas/sitemap/0.9",
  "xmlns:image" => "http://www.google.com/schemas/sitemap-image/1.1"
) do

  @pages.each do |page|
    xml.url do
      xml.loc     page[:uri].to_s
      xml.lastmod page[:updated_at].strftime('%Y-%m-%d')

      page[:pictures].each do |picture|
        xml.image(:image) do
          xml.image(:loc, picture[:loc])
          xml.image(:title, page[:title]) if page[:title].present?
          xml.image(:caption, picture[:caption]) if picture[:caption].present?
        end
      end
    end
  end
end
