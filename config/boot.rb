ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.
require 'bootsnap/setup' # Speed up boot  by caching expensive operations.

# Disable YAML caching in bootsnap
ENV['DISABLE_BOOTSNAP_YAML_CACHE'] = 'true'
