#lib/tasks/import.rake

desc 'Import LTCs'

require 'csv'
namespace :csv do

	task :import => :environment do
		CSV.foreach("#{Rails.root}/lib/ltc.csv", :headers => true, :encoding => 'ISO-8859-1:UTF-8') do |row|
      row.to_hash
      #row["category"] = Category.where(:name => row["category"]).first_or_create!
      #Company.create(row)

      cat = Category.where(:name => row["category"]).first_or_create!
      count = row["employee_count"]
      if count.nil?
        count = 1
      elsif count < 1
        count = 1
      end

      c = Company.where(:name => row["name"]).first_or_create!(
        :name => row["name"],
        :location => row["location"],
        :founded_date => row["founded_date"],
        :category => cat,
        :description => row["description"],
        :main_url => row["main_url"],
        :twitter_url => row["twitter_url"],
        :angellist_url => row["angellist_url"],
        :crunchbase_url => row["crunchbase_url"],
        :employee_count => count
      )
      
    end
	end
end
