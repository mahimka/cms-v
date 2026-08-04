task :check_brands do

  SnapShot.joins(:profile).where(profile: {profileable_type: 'Item'}).all.each do |shot|
    puts shot.profile.url + 'NO brand' if shot.labels['brand'] == ''
  end
end


task :terms_count do 
  term_counts = Hash.new(0)
  SnapShot.joins(:profile).where(profile: { profileable_type: 'Item' }).find_each do |shot|
    # Пропускаем, если у шота нет описания/html-контента (замените :body на ваше поле с HTML)
    next if shot.html_content.blank?

    # Парсим HTML шота через Nokogiri
    doc = Nokogiri::HTML(shot.html_content)
    # Ищем все теги <strong> и проверяем их на двоеточие на конце
    doc.search('strong').each do |strong|
      text = strong.text.strip

      if text.end_with?(':')
        term = text.chomp(':').strip
        term_counts[term] += 1 unless term.empty?
      end
    end
  end

  # Результат (хэш: термин => количество)
  puts term_counts.inspect
end


task :parse_shots do 

  SnapShot.joins(:profile).where(profile: {profileable_type: 'Item'}).all.sample(100).each do |shot|
    
    doc = Nokogiri::HTML(shot.html_content)
    
    h1 = doc.at_css('h1').text
    puts h1# + shot.profile.url
    name = h1.sub(/^.+?\s+[–-]\s+/, '')
    puts name


    volume = ''
    name = name.sub(/,\s*(\d+[a-zA-Z]+)$/) do
      volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
      ''          # Заменяем найденную часть на пустую строку (удаляем из text)
    end

    name = name.sub(/\s+[–-]\s+(\d+[a-zA-Z]+)$/) do
      volume = $1 # Сохраняем "50ml"
      ''          # Удаляем из строки
    end

    name = name.sub(/\s(\d+[a-zA-Z]+)$/) do
      volume = $1 # Сохраняем "50ml"
      ''          # Удаляем из строки
    end

    name = name.sub(/,\s*(\d+\s[a-zA-Z]+)$/) do
      volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
      ''          # Заменяем найденную часть на пустую строку (удаляем из text)
    end

    name = name.sub(/\s*(\d+\s[a-zA-Z]+)$/) do
      volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
      ''          # Заменяем найденную часть на пустую строку (удаляем из text)
    end

    puts name
    puts volume

    ean = doc.at_css('h2.qudo-ean')&.text&.sub('EAN: ', '')
    puts ean

    def extract_categories(doc)
      # Ищем элемент с классом posted_in и собираем текст из всех тегов <a> внутри него
      categories = doc.css('.posted_in a').map { |a| a.text.strip unless a['href'].include?('brand') }
      
      # Возвращаем массив категорий (он будет пустым [], если блок не найден)
      categories.compact
    end
    categories = extract_categories(doc)

    brand = ''
    doc.css('span.posted_in').each do |node|
      # categories << node.text.sub('Category: ', '') if node.text.starts_with?('Category:') 

      brand = node.text.sub('Brand: ', '') if node.text.starts_with?('Brand:') 

    end

    puts categories.inspect
    puts brand.inspect

    puts
    

  end

  
end


# task :seed_sites do 
#   # Site.create(name: "qudoBeauty", url: "https://qudobeauty.com/", domain: "qudobeauty.com")
# end

# task :list_profiles do 
#   Profile.where(profileable_type: "Item").each do |profile|
#     puts profile.inspect
#   end
#   puts Profile.all.size
# end


# task :list_shots do 
#   SnapShot.all.each do |profile|
#     puts profile.inspect
#   end
#   puts Profile.all.size
# end



def extract_attribute(doc, label)


  doc = doc.gsub(/<strong\b[^>]*>/i, '').gsub('</strong>', '')

  # Экранируем спецсимволы в label (например, двоеточие)
  escaped_label = Regexp.escape(label)
  
  # Находим label, пропускаем возможные пробелы и забираем всё до первого тега <
  pattern = /#{escaped_label}\s*([^<]+)/i

  match = doc.match(pattern)
  result = match ? match[1].strip : nil

  if result && result.include?('/')
    result = result.split('/').map{|word| word.strip }

  elsif result && result.include?('+')
    result = result.split('+').map{|word| word.strip }
  elsif result && result.include?('x')
    result = result.split('x').map{|word| word.strip }
  end

  result = [result] if result.is_a?(String)
  result = result.map{|word| word.gsub('.', '')} if result.is_a?(Array)

end


def extract(doc, starts_with, ends_with)

  doc = doc.gsub(/<\/??span\b[^>]*>/i, '') #! <span class="BZ_Pyq_fadeIn">How </span><span class="BZ_Pyq_fadeIn">to </span>

  # Экранируем спецсимволы в поиске
  start_pattern = Regexp.escape(starts_with)
  end_pattern   = Regexp.escape(ends_with)

  # Ищем теги <strong> с любыми атрибутами
  pattern = /<strong\b[^>]*>\s*#{start_pattern}\s*<\/strong>(.*?)<strong\b[^>]*>\s*#{end_pattern}\s*<\/strong>/m

  # puts pattern

  match = doc.match(pattern)
  block_found = match ? match[1].strip : nil

  return nil if block_found.nil?

  # 2. Удаляем экранированные текстовые переносы (буквальный \n в строке)
  block_found = block_found
      .gsub(/[\r\n]+/, ' ')
      .gsub("\n", ' ')      # 1. Заменяем ВСЕ \n и \r на пробел
      # .gsub(/<[^>]+>/, ' ')      # 2. Удаляем любые HTML-теги
      .then { |t| CGI.unescapeHTML(t) } # 3. &amp; -> &
      .gsub(/\s+/, ' ')  
      .gsub('• ', '')        # 4. Схлопываем множественные пробелы
      .strip

  block_found = block_found.gsub(/<\/??span\b[^>]*>/i, '')
  block_found = block_found.gsub(/<\/??strong\b[^>]*>/i, '')
  # Заменяем любой тег (<...>) на перенос строки
  block_found = block_found.gsub(/<[^>]+>/, "my-splitter ").strip
  block_found = block_found.gsub(/my-splitter\s+/, "my-splitter ").strip
  block_found = block_found.split('my-splitter').delete_if{|tag| tag.blank?}.map{|tag| tag.strip}
end

task :parse_shots_3 do 

  errors_report = []
  # SnapShot.where(param_1: [nil, '']).joins(:profile).where(profile: {profileable_type: 'Item'}).all.each do |shot|
  SnapShot.where(param_1: [nil, '']).joins(:profile).where(profile: {profileable_type: 'Item'}).all.each do |shot|
    
    begin

      # doc = shot.html_content.gsub(/<\/??span\b[^>]*>/i, '')  #! <span class="BZ_Pyq_fadeIn">How </span><span class="BZ_Pyq_fadeIn">to </span>
      doc = shot.html_content

      result = {}

      # 1. Первый блок текста (до Product contains:)
      # Ищем первый тег <p>, у которого нет внутри <strong> с заголовками секций
      doc_noko = Nokogiri::HTML(doc)
      first_p = doc_noko.at('div.entry-content > p:first-of-type')
      result['Description'] = first_p ? first_p.text.strip : ''

      if !extract(doc, "Product contains:", "Product effects:").blank? 
        result["Product contains"] = extract(doc, "Product contains:", "Product effects:")
      end

      if !extract(doc, "Product effects:", "Recommended for:").blank? 
        result["Product effects"] = extract(doc, "Product effects:", "Recommended for:")
      elsif !extract(doc, "Product effects:", "Our cosmetologist recommends this product in case of:").blank? 
        result["Product effects"] = extract(doc, "Product effects:", "Our cosmetologist recommends this product in case of:")
      end

      if !extract(doc, "Recommended for:", "How to use:").blank? 
        result["Recommended for"] = extract(doc, "Recommended for:", "How to use:")
      elsif !extract(doc, "Our cosmetologist recommends this product in case of:", "How to use:").blank? 
        result["Recommended for"] = extract(doc, "Our cosmetologist recommends this product in case of:", "How to use:")
      end

      if !extract_how_to_use(doc).blank? 
        result["How to use"] = extract_how_to_use(doc)
      end

      result["Capacity"] = extract_attribute(doc, 'Capacity:') 
      result["Volume"] = extract_attribute(doc, 'Volume:') 
      result["Fragrance family"] = extract_attribute(doc, 'Fragrance family:') 
      result["Country of origin"] = extract_attribute(doc, 'Country of origin:') 

      result["name"] = extract_name(doc)
      result["vol"] = extract_volume(doc)
      result["ean"] = extract_ean(doc)
      result["brand"] = extract_brand(doc)
      result["categories"] = extract_categories(doc)

      require 'pp'

      puts shot.profile.url
      # pp result if result.length > 0
      pp result #if result["Capacity"] 
      puts
      
      shot.param_1 = result["name"]
      shot.param_2 = result["vol"]
      shot.param_3 = result["ean"]
      shot.param_4 = result["brand"]
      shot.labels = result

      shot.save

    rescue StandardError => e
      # Сохраняем подробную информацию об ошибке
      errors_report << {
        url: shot.profile.url,
        error_class: e.class.to_s,
        message: e.message,
        location: e.backtrace.first(5)
      }

      # Переходим к следующему элементу цикла
      next
    end

  end

  pp errors_report

end


task :delete_wrong_shots do 

  # puts SnapShot.all.length
  # puts SnapShot.where(html_content: [nil, '']).length
  # puts SnapShot.where(html_content: [nil, '']).delete_all
  # puts SnapShot.all.length
  # puts SnapShot.where(html_content: [nil, '']).length
  puts SnapShot.where(param_1: [nil, '']).length

  # table_name = SnapShot.table_name

  # ActiveRecord::Base.connection.execute(<<~SQL)
  #   UPDATE sqlite_sequence 
  #   SET seq = (SELECT COALESCE(MAX(id), 0) FROM #{table_name}) 
  #   WHERE name = '#{table_name}';
  # SQL


end


def extract_how_to_use(doc)

    doc = doc.gsub(/<\/??span\b[^>]*>/i, '')

    how_to_use = []

    doc_noko = Nokogiri::HTML(doc)
  
    # strong_node = doc_noko.xpath(".//strong[normalize-space(text())='#{title_text}']").first
    strong_node = doc_noko.xpath(".//strong[normalize-space(text())='How to use:']").first
    return nil unless strong_node
    
    # 2. Поднимаемся к родительскому тегу <p> или берем следующий элемент, если они разделены
    parent_tag = strong_node.parent

    if parent_tag && parent_tag.at_css('br')
       how_to_use << parent_tag.text.strip.sub('How to use:', '').split('.').map{|tag| tag.strip}
    end


    # Случай А: Если список идет СЛЕДУЮЩИМ элементом (как ul для Product contains)
    next_element = parent_tag.next_element

    if next_element && next_element.name == 'ul'
      next_element.search('li').each do |li|
         how_to_use << li.text.strip
      end
    end

    if next_element && next_element.name == 'p'
      unless  ['Capacity', 'Volume', 'Fragrance family', 'Country of'].any? { |word| next_element.text.include?(word) }       
        how_to_use << next_element.text.strip.split('.')
      end
     end

    how_to_use = how_to_use.flatten

end


def extract_name(doc)

  doc = Nokogiri::HTML(doc)
  
  h1 = doc.at_css('h1').text
  name = h1.sub(/^.+?\s+[–-]\s+/, '')

  name = name.sub(/,\s*(\d+[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
    ''          # Заменяем найденную часть на пустую строку (удаляем из text)
  end

  name = name.sub(/\s+[–-]\s+(\d+[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем "50ml"
    ''          # Удаляем из строки
  end

  name = name.sub(/\s(\d+[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем "50ml"
    ''          # Удаляем из строки
  end

  name = name.sub(/,\s*(\d+\s[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
    ''          # Заменяем найденную часть на пустую строку (удаляем из text)
  end

  name = name.sub(/\s*(\d+\s[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
    ''          # Заменяем найденную часть на пустую строку (удаляем из text)
  end

  # puts name
  # puts volume if defined?(volume)

  name if defined?(name)

end  

def extract_volume(doc)

  doc = Nokogiri::HTML(doc)

  volume = ''
  
  h1 = doc.at_css('h1').text
  name = h1.sub(/^.+?\s+[–-]\s+/, '')

  name = name.sub(/,\s*(\d+[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
    ''          # Заменяем найденную часть на пустую строку (удаляем из text)
  end

  name = name.sub(/\s+[–-]\s+(\d+[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем "50ml"
    ''          # Удаляем из строки
  end

  name = name.sub(/\s(\d+[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем "50ml"
    ''          # Удаляем из строки
  end

  name = name.sub(/,\s*(\d+\s[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
    ''          # Заменяем найденную часть на пустую строку (удаляем из text)
  end

  name = name.sub(/\s*(\d+\s[a-zA-Z]+)$/) do
    volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
    ''          # Заменяем найденную часть на пустую строку (удаляем из text)
  end

  volume if defined?(volume)

end  

def extract_ean(doc)
  doc = Nokogiri::HTML(doc)
  ean = doc.at_css('h2.qudo-ean')&.text&.sub('EAN: ', '')
  ean if defined?(ean)
end  

def extract_brand(doc)
  brand = ''
  doc = Nokogiri::HTML(doc)
  doc.css('span.posted_in').each do |node|
    brand = node.text.sub('Brand: ', '') if node.text.starts_with?('Brand:') 
  end
  brand if defined?(brand)
end  

def extract_categories(doc)
  doc = Nokogiri::HTML(doc)
  categories = doc.css('.posted_in a').map { |a| a.text.strip unless a['href'].include?('brand') }
  # Возвращаем массив категорий (он будет пустым [], если блок не найден)
  categories.compact if defined?(categories)
end 





# task :parse_shots do 

#   SnapShot.joins(:profile).where(profile: {profileable_type: 'Item'}).all.sample(100).each do |shot|
    
#     doc = Nokogiri::HTML(shot.html_content)
    
    # h1 = doc.at_css('h1').text
    # puts h1# + shot.profile.url
    # name = h1.sub(/^.+?\s+[–-]\s+/, '')
    # puts name


    # volume = ''
    # name = name.sub(/,\s*(\d+[a-zA-Z]+)$/) do
    #   volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
    #   ''          # Заменяем найденную часть на пустую строку (удаляем из text)
    # end

    # name = name.sub(/\s+[–-]\s+(\d+[a-zA-Z]+)$/) do
    #   volume = $1 # Сохраняем "50ml"
    #   ''          # Удаляем из строки
    # end

    # name = name.sub(/\s(\d+[a-zA-Z]+)$/) do
    #   volume = $1 # Сохраняем "50ml"
    #   ''          # Удаляем из строки
    # end

    # name = name.sub(/,\s*(\d+\s[a-zA-Z]+)$/) do
    #   volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
    #   ''          # Заменяем найденную часть на пустую строку (удаляем из text)
    # end

    # name = name.sub(/\s*(\d+\s[a-zA-Z]+)$/) do
    #   volume = $1 # Сохраняем то, что нашлось в скобках (например, "50ml")
    #   ''          # Заменяем найденную часть на пустую строку (удаляем из text)
    # end

    # puts name
    # puts volume

    # ean = doc.at_css('h2.qudo-ean')&.text&.sub('EAN: ', '')
    # puts ean

    # def extract_categories(doc)
    #   # Ищем элемент с классом posted_in и собираем текст из всех тегов <a> внутри него
    #   categories = doc.css('.posted_in a').map { |a| a.text.strip unless a['href'].include?('brand') }
      
    #   # Возвращаем массив категорий (он будет пустым [], если блок не найден)
    #   categories.compact
    # end
    # categories = extract_categories(doc)

    # brand = ''
    # doc.css('span.posted_in').each do |node|
    #   # categories << node.text.sub('Category: ', '') if node.text.starts_with?('Category:') 

    #   brand = node.text.sub('Brand: ', '') if node.text.starts_with?('Brand:') 

    # end

    # puts categories.inspect
    # puts brand.inspect

    # puts
    

#   end

  
# end
