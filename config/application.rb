require_relative 'boot'
require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Legaltechlist
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    config.time_zone = 'UTC'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    config.i18n.default_locale = :en

    # Keep your existing Rails 5 configurations
    config.action_controller.per_form_csrf_tokens = true
    config.action_controller.forgery_protection_origin_check = true
    config.active_record.belongs_to_required_by_default = true
    
    # Keep your optional settings
    config.ssl_options = { hsts: { subdomains: true } }
    config.action_mailer.perform_caching = false

    # Keep your custom configurations
    config.twitter_list_url = ENV['TWITTER_LIST_URL'] || "https://twitter.com/CodeX_Law/lists/legal-tech-companies"

    # Add this line to autoload the services directory
    config.autoload_paths += %W(#{config.root}/app/services)

    # Add after your existing configurations
    config.active_support.cache_format_version = 7.0
    config.active_support.remove_deprecated_time_with_zone_name = true
    config.active_support.executor_around_test_case = true
  end
end
