require 'yaml'
YAML.load_file(Rails.root.join('config/database.yml'), aliases: true) if File.exist?(Rails.root.join('config/database.yml'))
