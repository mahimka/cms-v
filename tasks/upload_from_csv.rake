#require_relative '../config/deploy.rb' if APP_ENV == "development" # чтобы не хранить пароль в файле на сервере??

require 'csv'

task :puts_big_spirits do
  puts BigSpirit.all.size.to_s
end

task :puts_boozes do
  puts Booze.all.size.to_s
end



task :insert_big_spirits___ do
  file = File.open("public/2022-09-06_15-38_Combined.csv", "r:iso-8859-1")
  CSV.parse(file, :col_sep => ';', :headers => true) do |row| # , :quote_char => "|"
    # puts row
    BigSpirit.create!({:articul => row[0],
                       :product => row[1], 
                       :vol     => row[2].to_f, 
                       :size    => row[3].to_f, 
                       :group   => row[4], 
                       :price   => row[5].to_f, 
                       :scale   => row[6],
                       :stock   => row[7].to_i,
                       :link    => row[8]
    })
  end
end  

task :fill_in_boozes do
 #  vol = {
 #  " 47% Vol." => "blue",
 #  " 43.3% Vol." => "green",
 #  " 40% Vol." => "red",
 #  " 45% Vol." => "red",
 # }



  BigSpirit.first(100).each do |bs|
    clean_name = bs.product.gsub(/\s\d{1,2}(\,\d{1,2}|)\%\sVol\./, "") # 22% Vol.
    clean_name = clean_name.gsub(/\s\d+(\,\d{1,2}|)l/, "") # 0,73l
    clean_name = clean_name.gsub(/ in Giftbox/, "") 
    puts clean_name

    booze = Booze.find_or_create_by(name: clean_name)
    booze.vol = bs.product[/\s\d{1,2}(\,\d{1,2}|)\%\sVol\./]
    booze.details[:size] = bs.product[/\s\d+(\,\d{1,2}|)l/]
    booze.group = bs.group
    booze.packing = bs.product[/ in Giftbox/]

    booze.save

  end   
end



# # settings.serialize_data ***
# unless settings.send("#{table_name.singularize}_to_baza_objects")['serialize_data'].nil?
#   values_hash = {}
#   settings.send("#{table_name.singularize}_to_baza_objects")['serialize_data'].split(" ").each do |node|
#      values_hash[node] = import.send(node) 
#   end
#   baza_object.facts = values_hash # это store поле!!!
# end

  # <% vol << bs.product[/\s\d{1,2}(\,\d{1,2}|)\%\sVol\./] # 22% Vol. %>
  # <% size << bs.product[/\s\d+(\,\d{1,2}|)l/] # 0,73l %>
  # <% gift << bs.product[/ in Giftbox/] # 22% Vol. %>