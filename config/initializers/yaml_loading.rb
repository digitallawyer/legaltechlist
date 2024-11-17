# Monkey patch Rails' YAML loading to enable aliases
module Rails
  class Application
    class Configuration
      def database_configuration
        require "yaml"
        require "erb"
        yaml = ERB.new(IO.read("config/database.yml")).result
        YAML.safe_load(yaml, aliases: true) || {}
      end
    end
  end
end

# Patch ActiveRecord's YAML loading
if defined?(ActiveRecord)
  module ActiveRecord
    class Base
      def self.configurations
        Rails.application.config.database_configuration
      end
    end
  end
end
