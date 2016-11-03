require 'csv'

class ImportCSVtoCompany
  class << self
    
    def import(csv_data)

  		CSV.foreach(csv_data.tempfile, :headers => true, :encoding => 'ISO-8859-1:UTF-8') do |row|

        row.to_hash
        
        row["name"] = row["name"].strip
        
        if row["name"]!=""
          # clean up data to ensure validation on import

          if row["contact_name"].nil? || row["contact_name"] == ""
            row["contact_name"] = "Unknown"
          end
      
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
            :contact_name => row["contact_name"],
            :contact_email => row["contact_email"],
            :name => row["name"],
            :location => row["location"],
            :founded_date => row["founded_date"],
            :visible => row["visible"],
            :category => cat,
            :sub_category => sub,
            :target_client => trg,
            :business_model => biz,
            :description => row["description"],
            :main_url => row["main_url"],
            :twitter_url => row["twitter_url"],
            :angellist_url => row["angellist_url"],
            :crunchbase_url => row["crunchbase_url"],
            :codex_presenter => row["codex_presenter"],
            :codex_presentation_date => row["codex_presentation_date"]
          )
        end
      end
    end
    
    def export(csv)
      
      # NOTE! The order of this list must match the order of the rows (below)
      header =  [
        "contact_name", 
        "contact_email", 
        "name", 
        "location",
        "founded_date",
        "visible", 
        "category",
        "target_client",
        "business_model",
        "description",
        "main_url",
        "twitter_url",
        "angellist_url",
        "crunchbase_url",
        "all_tags",
        "codex_presenter",
        "codex_presentation_date"
      ]
      
      csv << header
      
      Company.all.each do |company|
        category = company.category.name
        
        if company.sub_category.present? 
          category = "#{company.category.name} - #{company.sub_category.name}" 
        end

        if company.target_client.present? 
          trg = company.target_client.name
        end
        
        if company.business_model.present? 
          biz = company.business_model.name
        end
        
        row = [
          company.contact_name,
          company.contact_email,
          company.name,
          company.location,
          company.founded_date,
          company.visible,
          category,
          trg,
          biz,
          company.description,
          company.main_url,
          company.twitter_url, 
          company.angellist_url, 
          company.crunchbase_url, 
          company.all_tags,
          company.codex_presenter,
          company.codex_presentation_date
         ]
        
        csv << row
      end

    end
    
  end
end