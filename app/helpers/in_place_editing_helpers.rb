module InPlaceEditingHelpers


  def translate_input(object, column, **options)

    defaults = {
      url_prefix:  '/admin',
      class:       "button is-warning is-small ml-1 mr-0",
      class_extra: "",
      style:       ""
    }

    options = defaults.merge(options)

    url_prefix  = options[:url_prefix]
    css_class   = options[:class] + ' ' +options[:class_extra]
    css_style   = options[:style] 

    object_name = object.class.name 


    # '/admin/translate/:table_name/:object_id/:column/ajax'
     
    ret = <<-EOM

      <script>
        $(document).ready(function(){

          $("a#translate_#{object_name}_#{object.id}_#{column}").click(function(){

            var object_id = $(this).attr('id').replace("translate_#{object_name}_", "").replace("_#{column}", "");

            var value = $(this).val();
            $.ajax({url: "#{url_prefix}/translate/#{object_name}/" + object_id + "/#{column}/ajax" + value, success: function(result){

              if (result != "") {
                $("##{object_name.downcase}_#{column}").fadeOut(300).fadeIn(300);
                $("##{object_name.downcase}_#{column}").val(result);
                $("##{object_name.downcase}_#{column}").addClass('is-danger');

              } else {
                $("##{object_name}_#{column}_#{object.id}").html("not saved!!!");
              }
            }
            });

          }); 
          
        });

      </script>
     
      <a class='#{css_class}' id='translate_#{object_name}_#{object.id}_#{column}'>tr</a>
    EOM



  end


  def input_in_place(object, column, **options)

    defaults = {
      url_prefix:  '/admin',
      class:       "input is-success is-small mt-1",
      class_extra: "",
      style:       "",
      placeholder: "enter #{object.class.name}##{column}"
    }

    options = defaults.merge(options)

    url_prefix  = options[:url_prefix]
    css_class   = options[:class] + ' ' +options[:class_extra]
    css_style   = options[:style] 
    placeholder = options[:placeholder]

    object_name = object.class.name 

    ret = <<-EOM

      <script>
        $(document).ready(function(){

          $("input[type=text].#{object_name}_#{column}_#{object.id}").change(function(){

            var object_id = $(this).attr('id').replace("#{object_name}_#{column}_", "");
            var value = $(this).val();
            $.ajax({url: "#{url_prefix}/#{object_name.tableize}/" + object_id + "/ajax?#{column}=" + value, success: function(result){

              if (result == "saved") {
                $("##{object_name}_#{column}_#{object.id}").fadeOut(300).fadeIn(300);
              } else {
                $("##{object_name}_#{column}_#{object.id}").html("not saved!!!");
              }
            }
            });

          }); 
          
        });

      </script>

      <input class="#{css_class} #{object_name}_#{column}_#{object.id}" style="#{css_style}"
             id="#{object_name}_#{column}_#{object.id}" 
             name="#{object_name}_#{column}[#{object.id}]" 
             placeholder="#{placeholder}"
             type="text" 
             value="#{object.send(column)}">
    EOM
      
  end  

  def textarea_in_place(object, column, **options)
    
    defaults = {
      url_prefix:  '/admin',
      class:       "input is-success is-small mt-1",
      class_extra: "",
      style:       "",
      placeholder: "enter #{object.class.name}##{column}"
    }

    options = defaults.merge(options)

    url_prefix  = options[:url_prefix]
    css_class   = options[:class] + ' ' +options[:class_extra]
    css_style   = options[:style] 
    placeholder = options[:placeholder]

    object_name = object.class.name.parameterize


    # height = 'height:30px;' 

    # if  object.send(column) && object.send(column)&.lines&.count > 1
    # # if  object.send(column).length > 200
    #    tall = object.send(column)&.lines&.count*20
    #    height = "height:#{tall}px;" 
    # end

    rows = 1 
    if  object.send(column) && object.send(column)&.lines&.count > 1
    # if  object.send(column).length > 200
       rows = object.send(column)&.lines&.count
    end    

    ret = <<-EOM

      <script>

        $(document).ready(function(){

          $("textarea[type=text].#{object_name}_#{column}_#{object.id}").change(function(){

            var object_id = $(this).attr('id').replace("#{object_name}_#{column}_", "");
            var value = encodeURIComponent($(this).val());
            $.ajax({url: "#{url_prefix}/#{object_name.pluralize}/" + object_id + "/ajax?#{column}=" + value, success: function(result){

              if (result == "saved") {
                $("##{object_name}_#{column}_#{object.id}").fadeOut(300).fadeIn(300);
              } else {
                $("##{object_name}_#{column}_#{object.id}").html("not saved!!!");
              }
            }
            });

          }); 
          
        });

      </script>

      <textarea class="textarea #{css_class} #{object_name}_#{column}_#{object.id}" style="#{css_style} " rows=" #{rows}"
             id="#{object_name}_#{column}_#{object.id}" 

             name="#{object_name}_#{column}[#{object.id}]" 
             placeholder="#{placeholder}" 
             type="text" 
             >#{object.send(column)}</textarea>

    EOM

    # <input class="#{css_class}" id="item_styles_temp_1" name="item_styles_temp[1]" placeholder="" type="text" value="Hatha Yoga">
    # <%= input_in_place(item, :styles_temp) %>
    # <%= input(:item_styles_temp, item.id, options = {class: 'input is-success is-size-7', value: item.styles_temp, placeholder: ""}) %>

      
  end  






  def checkbox_in_place(object, column, **options)

    defaults = {
      url_prefix:  '/admin',
      class:       "checkbox is-success mt-1",
      class_extra: "",
      style:       ""
    }

    options = defaults.merge(options)

    url_prefix  = options[:url_prefix]
    css_class   = options[:class] + ' ' +options[:class_extra]
    css_style   = options[:style] 
    placeholder = options[:placeholder]    
    
    object_name = object.class.name.parameterize

    ret = <<-EOM

      <script>
        $(document).ready(function(){

          //$("input[type=checkbox]").change(function(){
          $("input[type=checkbox]##{object_name}_#{column}_#{object.id}").change(function(){

            var object_id = $(this).attr('id').replace("#{object_name}_#{column}_", "");
            var status = (this.checked);

            $.ajax({url: "#{url_prefix}/#{object_name.pluralize}/" + object_id + "/ajax?#{column}=" + status, success: function(result){

              if (result == "saved") {
                $("##{object_name}_#{column}_#{object.id}").fadeOut(300).fadeIn(300);
              } else {
                $("##{object_name}_#{column}_#{object.id}").html("not saved!!!");
              }
            }
            });

          }); 
          
        });

      </script>
       
      <input id="#{object_name}_#{column}_#{object.id}" type="checkbox" value=true #{object.send(column) == true ? "checked='checked'" : ""} 
      title='#{column}' style="#{css_style}" class="#{css_class}">

    EOM

    # <input class="#{css_class}" id="item_styles_temp_1" name="item_styles_temp[1]" placeholder="" type="text" value="Hatha Yoga">
    # <%= input_in_place(item, :styles_temp) %>
    # <%= input(:item_styles_temp, item.id, options = {class: 'input is-success is-size-7', value: item.styles_temp, placeholder: ""}) %>

      
  end 




  def delete_in_place(object)
    
    object_name = object.class.name.parameterize

    ret = <<-EOM

      <script>
        $(document).ready(function(){

          $("#delete_nested_#{object_name}_#{object.id}").click(function(){

            var object_id = $(this).attr('id').replace("delete_nested_#{object_name}_", "");

            $.ajax({url: "/admin/#{object_name.pluralize}/" + object_id + "/ajax/delete", success: function(result){

              if (result == "deleted") {
                $("#nested_#{object_name}_#{object.id}").fadeOut(300).fadeIn(300);
                $("#nested_#{object_name}_#{object.id}").html("deleted");
              } else {
                $("#nested_#{object_name}_#{object.id}").html("not deleted!!!");
              }
            }

            });

          }); 
          
        });

      </script>



      <a id='delete_nested_#{object.class.name.parameterize}_#{object.id}' class='' ><i class='fas fa-times-circle '></i></a>

    EOM

    # <input class="#{css_class}" id="item_styles_temp_1" name="item_styles_temp[1]" placeholder="" type="text" value="Hatha Yoga">
    # <%= input_in_place(item, :styles_temp) %>
    # <%= input(:item_styles_temp, item.id, options = {class: 'input is-success is-size-7', value: item.styles_temp, placeholder: ""}) %>

      
  end 


  def select_in_place(object, column, values, **options)

    defaults = {
      url_prefix:  '/admin',
      class:       "input is-success is-small mt-0",
      class_extra: "",
      style:       "",
      placeholder: "enter #{object.class.name}##{column}"
    }

    options = defaults.merge(options)

    url_prefix  = options[:url_prefix]
    css_class   = options[:class] + ' ' + options[:class_extra]
    css_style   = options[:style] 
    placeholder = options[:placeholder]    
    
    object_name = object.class.name 

    ret = <<-EOM

      <script>

        $(document).ready(function(){

          $("select.#{object_name}_#{column}_#{object.id}").change(function(){

            var object_id = $(this).attr('id').replace("#{object_name}_#{column}_", "");
            var value = $(this).val();
            $.ajax({url: "#{url_prefix}/#{object_name.tableize}/" + object_id + "/ajax?#{column}=" + value, success: function(result){

              if (result == "saved") {
                $("##{object_name}_#{column}_#{object.id}").fadeOut(300).fadeIn(300);
              } else {
                $("##{object_name}_#{column}_#{object.id}").html("not saved!!!");
              }
            }
            });

          }); 
          
        });

      </script>

      <div class="control has-icons-right">
        <select autocomplete="off" class="#{css_class} #{object_name}_#{column}_#{object.id}" id="#{object_name}_#{column}_#{object.id}" name="#{object_name}_#{column}[#{object.id}]" 
        value="#{object.send(column)}" style="#{css_style}">

    EOM

    ret +="<option value=''></option>"
    
    if values.is_a? Array
      values.each do |val|
         ret +="<option value='#{val}' #{ val == object.send(column) ? "selected='selected'" : '' }>#{val}</option>"
      end
    elsif values.is_a? Hash
      values.each do |val, name|
         ret +="<option value='#{val}' #{ val.to_s == object.send(column).to_s ? "selected='selected'" : '' }>#{name}</option>"
      end
    end

    ret +=  '</select>'

     ret += <<-EOM

        <span class="icon is-small is-right">
          <i class="fas fa-caret-down"></i>
        </span>
      </div>
     EOM

    # <input class="#{css_class}" id="item_styles_temp_1" name="item_styles_temp[1]" placeholder="" type="text" value="Hatha Yoga">
    # <%= input_in_place(item, :styles_temp) %>
    # <%= input(:item_styles_temp, item.id, options = {class: 'input is-success is-size-7', value: item.styles_temp, placeholder: ""}) %>
        # <option value=""></option>
        # <option selected="selected" value="home">home</option>
        # <option value="index">index</option><option value="profile">profile</option>
      
  end  


end  