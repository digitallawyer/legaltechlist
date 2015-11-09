#lib/tasks/import.rake

desc 'Import LTCs'

require 'csv'
namespace :csv do

	task :import => :environment do
		CSV.foreach("#{Rails.root}/lib/ltc.csv", :headers => true, :encoding => 'ISO-8859-1:UTF-8') do |row|
      row.to_hash
      #row["category"] = Category.where(:name => row["category"]).first_or_create!
      #Company.create(row)

      # clean up data to ensure validation on import
      count = row["employee_count"]
      if count.nil?
        count = 1
      elsif count < 1
        count = 1
      end
      
      if row["business_model"].nil? || row["business_model"] == ""
        row["business_model"] = "Unknown"
      end
      
      if row["all_tags"].nil?
        row["all_tags"] = ""
      end

      if row["target_client"].nil? || row["target_client"] == ""
        row["target_client"] = "Unknown"
      end
        
      # split category into category and sub-category
      catFullname = row["category"].split('-')
      catName = catFullname[0].strip
      if catFullname[1].nil?
        catFullname[1]=""
      end
      
      cat = Category.where(:name => catName).first_or_create!
      sub = SubCategory.where(:name => catFullname[1],
                              :category => cat
                            ).first_or_create!(:name => catFullname[1],
                                               :category => cat)
      
      #find references
      biz = BusinessModel.where(:name => row["business_model"]).first
      trg = TargetClient.where(:name => row["target_client"]).first

      # add the entry to the database
      c = Company.where(:name => row["name"]).first_or_create!(
        :name => row["name"],
        :location => row["location"],
        :founded_date => row["founded_date"],
        :category => cat,
        :sub_category => sub,
        :description => row["description"],
        :main_url => row["main_url"],
        :twitter_url => row["twitter_url"],
        :angellist_url => row["angellist_url"],
        :crunchbase_url => row["crunchbase_url"],
        :employee_count => count,
        :business_model => biz,
        :target_client => trg,
        :all_tags => row["all_tags"]
      )
      
    end
	end
end
