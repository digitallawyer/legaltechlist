require 'csv'

class ImportCSVtoCompany
  class << self
    
    def import(csv_data)

  		CSV.foreach(csv_data.tempfile, :headers => true, :encoding => 'ISO-8859-1:UTF-8') do |row|

        row.to_hash
        
        row["name"] = row["name"].strip
        
        if row["name"]!=""
          # clean up data to ensure validation on import

      
          if row["business_model"].nil? || row["business_model"] == ""
            row["business_model"] = "Unknown"
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

          print "*************************************************\n"
          print "Add #{row["name"]}\n"
          print "*************************************************\n"
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
            :business_model => biz,
            :target_client => trg,
            :all_tags => row["all_tags"]
          )
        end
      end
    end
    
    def export(csv)
      
      # NOTE! The order of this list must match the order of the rows (below)
      header =  [
        "name", 
        "location",
        "founded_date",
        "category",
        "description",
        "main_url",
        "twitter_url",
        "angellist_url",
        "crunchbase_url",
        "business_model",
        "target_client",
        "all_tags"
      ]
      
      csv << header
      
      Company.all.each do |company|
        category = company.category.name
        
        if company.sub_category.name != "" 
          category = "#{company.category.name} - #{company.sub_category.name}" 
        end
        
        row = [
          company.name,
          company.location,
          company.founded_date,
          category,
          company.description,
          company.main_url,
          company.twitter_url, 
          company.angellist_url, 
          company.crunchbase_url, 
          company.business_model.name,
          company.target_client.name,
          company.all_tags
         ]
        
        csv << row
      end

    end
    
  end
end