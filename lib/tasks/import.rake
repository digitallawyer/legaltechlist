#lib/tasks/import.rake

desc 'Import LTCs'

require 'csv'
namespace :csv do

	task :import => :environment do
		CSV.foreach("#{Rails.root}/lib/ltc.csv", :headers => true, :encoding => 'ISO-8859-1:UTF-8') do |row|
	  		Company.create(row.to_hash)
	  	end
	end
end
