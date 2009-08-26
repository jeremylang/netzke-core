module Netzke
  # == BaseJs
  # Module which provides JS-class generation functionality for the widgets ("client-side"). The generated code 
  # is evaluated once per widget class, and the results are cached in the browser. Included into Netzke::Base class.
  # 
  # == Widget javascript code
  # Here's a brief explanation on how a javascript class for a widget gets built.
  # Widget gets defined as a constructor (a function) by +js_class+ class method (see "Inside widget's contstructor").
  # +Ext.extend+ provides inheritance from an Ext class specified in +js_base_class+ class method.
  # 
  # == Inside widget's constructor
  # * Widget's constructor gets called with a parameter that is a configuration object provided by +js_config+ instance method. This configuration is specific for the instance of the widget, and, for example, contains this widget's unique id. As another example, by means of this configuration object, a grid receives the configuration array for its columns, a form - for its fields, etc. With other words, everything that may change from instance to instance of the same widget's class, goes in here.
  # * Widget executes its specific initialization code which is provided by +js_before_consttructor+ class method. 
  # For example, a grid may define its column model, a form - its fields, a tab panel - its tabs ("items").
  # * Widget calls the constructor of the inherited class (see +js_class+ class method) with a parameter that is a merge of 
  # 1) common widget's configuration (for example, a grid may specify the earlier defined column model), which is provided by +js_common_config_for_constructor+ class method, 
  # 2) configuration parameter passed to the widget's constructor.
  module BaseJs
    def self.included(base)
      base.extend ClassMethods
    end

    #
    # Instance methods
    #

    # Config that is used for instantiating the widget in javascript
    def js_config
      res = {}
      
      # Unique id of the widget
      res.merge!(:id => id_name)
  
      # Recursively include configs of all non-late aggregatees, so that the widget can instantiate them
      # in javascript immediately.
      non_late_aggregatees.each_pair do |aggr_name, aggr_config|
        aggr_instance = aggregatee_instance(aggr_name.to_sym)
        aggr_instance.before_load
        res["#{aggr_name}_config".to_sym] = aggr_instance.js_config
      end
  
      # Api
      res.merge!(:api => self.class.api_points)
  
      # Widget class name. Needed for dynamic instantiation in javascript.
      res.merge!(:widget_class_name => short_widget_class_name)
      
      # Actions, toolbars and menus
      # tools   && res.merge!(:tools   => tools)
      actions && res.merge!(:actions => actions)
      menu    && res.merge!(:menu    => menu)

      # Merge with all config options passed as hash to config[:ext_config]
      res.merge!(ext_config)
  
      res
    end
  
    # All the JS-code required by this instance of the widget to be instantiated in the browser.
    # It includes the JS-class for the widget itself, as well as JS-classes for all widgets' (non-late) aggregatees.
    def js_missing_code(cached_dependencies = [])
      code = dependency_classes.inject("") do |r,k| 
        cached_dependencies.include?(k) ? r : r + "Netzke::#{k}".constantize.js_code(cached_dependencies).strip_js_comments
      end
      code.blank? ? nil : code
    end
    
    def css_missing_code(cached_dependencies = [])
      code = dependency_classes.inject("") do |r,k| 
        cached_dependencies.include?(k) ? r : r + "Netzke::#{k}".constantize.css_code(cached_dependencies)
      end
      code.blank? ? nil : code
    end
  
    #
    # The following methods are used when a widget is generated stand-alone (as a part of a HTML page)
    #

    # instantiating
    def js_widget_instance
      %Q{var #{name.jsonify} = new Ext.netzke.cache.#{short_widget_class_name}(#{js_config.to_nifty_json});}
    end

    # rendering
    def js_widget_render
      %Q{#{name.jsonify}.render("#{name.to_s.split('_').join('-')}");}
    end

    # container for rendering
    def js_widget_html
      %Q{<div id="#{name.to_s.split('_').join('-')}"></div>}
    end

    #
    #
    #
 
    # Widget's actions, tools and menus that are loaded at the moment of instantiation
    def actions; nil; end
    def menu; nil; end
    # def tools; nil; end

    # Little helpers
    def this; "this".l; end
    def null; "null".l; end

    # Methods used to create the javascript class (only once per widget class). 
    # The generated code gets cached at the browser, and the widget intstances (at the browser side)
    # get instantiated from it.
    # All these methods can be overwritten in case you want to extend the functionality of some pre-built widget
    # instead of using it as is (using both would cause JS-code duplication)
    module ClassMethods
      # the JS (Ext) class that we inherit from on JS-level
      def js_base_class
        "Ext.Panel"
      end

      # functions and properties that will be used to extend the functionality of (Ext) JS-class specified in js_base_class
      def js_extend_properties 
        {}
      end
  
      # widget's menus
      def js_menus; []; end
  
      # items
      def js_items; null; end
      
      # are we using JS inheritance? for now, if js_base_class is a Netzke class - yes
      def js_inheritance?
        superclass != Netzke::Base
      end

      # Declaration of widget's class (stored in the cache storage (Ext.netzke.cache) at the client side 
      # to be reused at the moment of widget instantiation)
      def js_class
        if js_inheritance?
          # In case of using javascript inheritance, little needs to be done
          <<-END_OF_JAVASCRIPT
          // Create the class
          Ext.netzke.cache.#{short_widget_class_name} = function(config){
            Ext.netzke.cache.#{short_widget_class_name}.superclass.constructor.call(this, config);
          };
          // Extend it with the class that we inherit from, and mix in js_extend_properties
          Ext.extend(Ext.netzke.cache.#{short_widget_class_name}, Ext.netzke.cache.#{superclass.short_widget_class_name}, Ext.applyIf(#{js_extend_properties.to_nifty_json}, Ext.widgetMixIn));
          END_OF_JAVASCRIPT
        else
          js_add_menus = "this.addMenus(#{js_menus.to_nifty_json});" unless js_menus.empty?
          <<-END_OF_JAVASCRIPT
          // Constructor
          Ext.netzke.cache.#{short_widget_class_name} = function(config){
            // Do all the initializations that every Netzke widget should do: create methods for API-points,
            // process actions, tools, toolbars
            this.commonBeforeConstructor(config);
            
            // Call the constructor of the inherited class
            Ext.netzke.cache.#{short_widget_class_name}.superclass.constructor.call(this, config);

            // What every widget should do after calling the constructor of the inherited class, like
            // setting extra events
            this.commonAfterConstructor(config);
          };
          Ext.extend(Ext.netzke.cache.#{short_widget_class_name}, #{js_base_class}, Ext.applyIf(#{js_extend_properties.to_nifty_json}, Ext.widgetMixIn));
          END_OF_JAVASCRIPT
        end
      end
      
      def css_include(*args)
        included_css = read_inheritable_attribute(:included_css) || []
        args.each do |inclusion|
          if inclusion.is_a?(Hash)
            # we are signalized a non-default file location (e.g. Ext examples)
            case inclusion.keys.first
            when :ext_examples
              location = Netzke::Base.config[:ext_location] + "/examples/"
            end
            files = inclusion.values.first
          else
            location = ""
            files = inclusion
          end
          
          files = [files] if files.is_a?(String)
          
          for f in files
            included_css << location + f
          end
        end
        write_inheritable_attribute(:included_css, included_css)
      end

      # all JS code needed for this class, including one from the ancestor widget
      def js_code(cached_dependencies = [])
        res = ""

        # include the base-class javascript if doing JS inheritance
        res << superclass.js_code << "\n" if js_inheritance? && !cached_dependencies.include?(superclass.short_widget_class_name)

        # include static javascripts
        res << js_included << "\n"

        # our own JS class definition
        res << js_class
        res
      end


      # Override this method. Must return an array of paths to javascript files that we depend on. 
      # This javascript code will be loaded along with the widget's class, and before it.
      def include_js
        []
      end

      # returns all extra js-code (as string) required by this widget's class
      def js_included
        res = ""

        include_js.each do |path|
          f = File.new(path)
          res << f.read << "\n"
        end

        res
      end

      
      # returns all extra js-code (as string) required by this widget's class
      def css_included
        res = ""
        
        included_css = read_inheritable_attribute(:included_css) || []
        res << included_css.inject("") do |r, path|
          f = File.new(path)
          r << f.read
        end

        res
      end
      
      # all JS code needed for this class including the one from the ancestor widget
      def css_code(cached_dependencies = [])
        res = ""

        # include the base-class javascript if doing JS inheritance
        res << superclass.css_code << "\n" if js_inheritance? && !cached_dependencies.include?(superclass.short_widget_class_name)
        
        res << css_included << "\n"
        
        res
      end

      def this; "this".l; end
      def null; "null".l; end
    
    end
  end
end