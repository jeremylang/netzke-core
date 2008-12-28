# NetzkeCore
require 'netzke/js_class_builder'
require 'netzke/base'
require 'netzke/core_ext'
require 'netzke/controller_extensions'

# Vendor
require 'vendor/facets/hash/recursive_merge'


%w{ models controllers }.each do |dir|
  path = File.join(File.dirname(__FILE__), 'app', dir)
  $LOAD_PATH << path
  ActiveSupport::Dependencies.load_paths << path
  ActiveSupport::Dependencies.load_once_paths.delete(path)
end

ActionController::Base.class_eval do
  include Netzke::ControllerExtensions
end

# Make this plugin reloadable for easier development
ActiveSupport::Dependencies.load_once_paths.delete(File.join(File.dirname(__FILE__)))

# Include the javascript
Netzke::Base.config[:javascripts] << "#{File.dirname(__FILE__)}/../javascripts/core.js"