require 'csv'

class ImportCsvToCompanyService
  class << self

    def import(csv_data)
      stats = { created: 0, updated: 0, skipped: 0, errors: 0 }

      CSV.foreach(csv_data.tempfile, :headers => true, :encoding => 'UTF-8') do |row|
        begin
          row.to_hash
          row["name"] = row["name"].to_s.strip

          if row["name"].blank?
            stats[:skipped] += 1
            next
          end

          # clean up data to ensure validation on import
          row["contact_name"] = "Unknown" if row["contact_name"].blank?
          row["business_model"] = "Unknown" if row["business_model"].blank?
          row["target_client"] = "Unknown" if row["target_client"].blank?
          row["category"] = "Unknown" if row["category"].blank?

          # split category into category and sub-category
          catName = row["category"].to_s.split('-').first.to_s.strip
          catName = "Unknown" if catName.blank?

          # Get subcategory if it exists, otherwise empty string
          subCatName = row["category"].to_s.split('-')[1].to_s.strip

          cat = Category.where(:name => catName).first_or_create!
          sub = SubCategory.where(:name => subCatName, :category => cat)
                          .first_or_create!(:name => subCatName, :category => cat)

          #find references
          biz = BusinessModel.where(:name => row["business_model"]).first_or_create!
          trg = TargetClient.where(:name => row["target_client"]).first_or_create!

          # Find existing company by trimmed name
          company = Company.where("TRIM(name) = ?", row["name"].strip).first

          attributes = {
            contact_name: row["contact_name"],
            contact_email: row["contact_email"],
            name: row["name"],
            location: row["location"],
            founded_date: row["founded_date"],
            visible: row["visible"].to_s.downcase == 'true',
            category: cat,
            sub_category: sub,
            target_client: trg,
            business_model: biz,
            description: row["description"],
            main_url: row["main_url"],
            twitter_url: row["twitter_url"],
            angellist_url: row["angellist_url"],
            crunchbase_url: row["crunchbase_url"],
            linkedin_url: row["linkedin_url"],
            facebook_url: row["facebook_url"],
            legalio_url: row["legalio_url"],
            status: row["status"],
            codex_presenter: row["codex_presenter"],
            codex_presentation_date: row["codex_presentation_date"]
          }

          if company
            # Update existing company if any attributes changed
            if company.attributes.except('id', 'created_at', 'updated_at') != attributes
              company.update!(attributes)
              # Update tags
              company.all_tags = row["all_tags"].to_s if row["all_tags"].present?
              stats[:updated] += 1
            else
              stats[:skipped] += 1
            end
          else
            # Create new company
            company = Company.create!(attributes)
            # Set tags
            company.all_tags = row["all_tags"].to_s if row["all_tags"].present?
            stats[:created] += 1
          end
        rescue => e
          Rails.logger.error "Error importing row: #{row.inspect}"
          Rails.logger.error e.message
          Rails.logger.error e.backtrace.join("\n")
          stats[:errors] += 1
        end
      end

      stats
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
        "linkedin_url",
        "facebook_url",
        "legalio_url",
        "status",
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
          company.linkedin_url,
          company.facebook_url,
          company.legalio_url,
          company.status,
          company.tags.any? ? company.all_tags : "",
          company.codex_presenter,
          company.codex_presentation_date
         ]

        csv << row
      end

    end

  end
end
