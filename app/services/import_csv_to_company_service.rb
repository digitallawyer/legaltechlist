require 'csv'

class ImportCsvToCompanyService
  class << self

    def import(csv_data)
      stats = { created: 0, updated: 0, skipped: 0, errors: 0 }

      CSV.foreach(csv_data.tempfile, :headers => true, :encoding => 'UTF-8') do |row|
        begin
          row.to_hash
          name = row["Organization Name"].to_s.strip

          if name.blank?
            stats[:skipped] += 1
            next
          end

          # Only import verified legal tech companies
          unless row["is_legal_tech"].to_s.downcase == 'true' && row["verified"].to_s.downcase == 'true'
            stats[:skipped] += 1
            next
          end

          # Clean up required fields
          business_model = row["suggested_business_model"] || "Unknown"
          target_client = row["suggested_target_client"] || "Unknown"
          category = row["suggested_category"] || "Unknown"

          # Get category and subcategory
          catName = category.to_s.split('-').first.to_s.strip
          catName = "Unknown" if catName.blank?
          subCatName = category.to_s.split('-')[1].to_s.strip

          # Create or find associated records
          cat = Category.where(:name => catName).first_or_create!
          sub = SubCategory.where(:name => subCatName, :category => cat).first_or_create! if subCatName.present?
          biz = BusinessModel.where(:name => business_model).first_or_create!
          trg = TargetClient.where(:name => target_client).first_or_create!

          # Find existing company
          company = Company.where("TRIM(name) = ?", name.strip).first

          # Parse exit date safely
          exit_date = begin
            row["Exit Date"].present? ? Date.parse(row["Exit Date"]) : nil
          rescue
            nil
          end

          # Determine funding status and stage
          funding_status = determine_funding_status(row)

          # Build a comprehensive description
          description_parts = []
          description_parts << row["Description"] if row["Description"].present?
          description_parts << "Industry: #{row['Industries']}" if row['Industries'].present?
          description_parts << "Stage: #{funding_status}" if funding_status.present?
          description_parts << "Operating Status: #{row['Operating Status']}" if row['Operating Status'].present?
          description_parts << row["verification_notes"] if row["verification_notes"].present?

          full_description = description_parts.join("\n\n").strip
          full_description = "No detailed description available." if full_description.blank?

          # Get location, with fallbacks
          location = clean_location(row["Headquarters Location"])
          if location.blank? && row["Headquarters Regions"].present?
            location = clean_location(row["Headquarters Regions"].split(',').first)
          end
          location ||= "Location unknown" # Final fallback

          attributes = {
            name: name,
            contact_name: row["Contact Name"] || "Unknown",
            contact_email: row["Contact Email"],
            location: location,
            founded_date: clean_date(row["Founded Date"]),
            visible: true, # All imported companies are verified
            category: cat,
            sub_category: sub,
            target_client: trg,
            business_model: biz,
            description: full_description,
            main_url: clean_url(row["Website"]),
            twitter_url: clean_url(row["Twitter"]),
            linkedin_url: clean_url(row["LinkedIn"]),
            facebook_url: clean_url(row["Facebook"]),
            status: row["Operating Status"],

            # Trend analysis fields
            number_of_funding_rounds: row["Number of Funding Rounds"].to_i,
            total_funding_usd: clean_funding_amount(row),
            funding_status: funding_status,
            exit_date: exit_date,
            founders: row["Founders"],
            headquarters_region: row["Headquarters Regions"],

            # Skip geocoding during import
            skip_geocoding: true
          }

          if company
            if company.attributes.except('id', 'created_at', 'updated_at') != attributes
              company.assign_attributes(attributes)
              company.skip_geocoding = true
              company.save!
              company.all_tags = row["suggested_tags"].to_s if row["suggested_tags"].present?
              stats[:updated] += 1
            else
              stats[:skipped] += 1
            end
          else
            company = Company.new(attributes)
            company.skip_geocoding = true
            company.save!
            company.all_tags = row["suggested_tags"].to_s if row["suggested_tags"].present?
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

    private

    def clean_location(location)
      return nil if location.blank?

      # Extract city and country, removing special characters
      parts = location.split(',').map { |part| part.strip.gsub(/[^\p{L}\p{N}\s,]/, '') }
      return parts.first if parts.size == 1

      [parts.first, parts.last].join(', ')
    end

    def clean_date(date_string)
      return nil if date_string.blank?

      # Handle obviously wrong dates
      return nil if date_string.start_with?('15') # Exclude 1500s dates

      # Extract year
      if date_string.match?(/^\d{4}/)
        date_string[0..3] # Get just the year
      else
        begin
          Date.parse(date_string).year.to_s
        rescue
          nil
        end
      end
    end

    def clean_url(url)
      return nil if url.blank?

      # Ensure URL has protocol
      unless url.start_with?('http://', 'https://')
        url = "https://#{url}"
      end

      url
    end

    def normalize_company_name(name)
      return nil if name.blank?

      # Remove common suffixes and clean up
      name.gsub(/\b(llc|ltd|inc|corp|corporation|limited)\b/i, '')
          .gsub(/[^\w\s-]/, '') # Remove special characters
          .squeeze(' ')         # Remove multiple spaces
          .strip
          .downcase
    end

    def map_input_row(row)
      {
        'name' => normalize_company_name(row['Organization Name']),
        'main_url' => clean_url(row['Website']),
        'location' => clean_location(row['Headquarters Location']),
        'founded_date' => clean_date(row['Founded Date']),
        'description' => row['Description'].to_s.strip,
        'twitter_url' => clean_url(row['Twitter']),
        'linkedin_url' => clean_url(row['LinkedIn']),
        'facebook_url' => clean_url(row['Facebook']),
        'status' => row['Operating Status'],
        'category' => row['suggested_category'],
        'stage' => row['Stage'],
        'company_type' => row['Company Type'],
        'funding_rounds' => row['Number of Funding Rounds'].to_i,
        'total_funding_usd' => row['Total Funding Amount (in USD)'].to_d,
        'funding_status' => row['Funding Status'],
        'founders' => row['Founders'],
        'contact_email' => row['Contact Email'],
        'headquarters_region' => row['Headquarters Regions']&.split(',')&.first&.strip,

        # Preserve original values for reference
        'Organization Name' => row['Organization Name'],
        'Website' => row['Website'],
        'Headquarters Location' => row['Headquarters Location'],
        'Founded Date' => row['Founded Date'],
        'Description' => row['Description'],
        'Twitter' => row['Twitter'],
        'LinkedIn' => row['LinkedIn'],
        'Facebook' => row['Facebook'],
        'Operating Status' => row['Operating Status'],
        'Stage' => row['Stage'],
        'Company Type' => row['Company Type'],
        'Number of Funding Rounds' => row['Number of Funding Rounds'],
        'Total Funding Amount (in USD)' => row['Total Funding Amount (in USD)'],
        'Funding Status' => row['Funding Status'],
        'Founders' => row['Founders'],
        'Contact Email' => row['Contact Email']
      }
    end

    def valid_for_import?(row)
      return false if row['name'].blank?
      return false if row['is_legal_tech'] != 'true'
      return false if row['verified'] != 'true'
      return false if row['founded_date'].blank?
      true
    end

    def determine_funding_status(row)
      # Check for exit events first
      return 'IPO' if row['Operating Status'].to_s.match?(/ipo|public/i)
      return 'M&A' if row['Operating Status'].to_s.match?(/acquired|merged/i) || row['Exit Date'].present?

      # Then check funding status
      funding_status = row['Funding Status'].to_s.strip
      return funding_status if funding_status.present?

      # If no funding status but has funding rounds, assume Early Stage
      return 'Early Stage Venture' if row['Number of Funding Rounds'].to_i > 0

      # Default to Operating
      'Operating'
    end

    def clean_funding_amount(row)
      amount = row['Total Funding Amount (in USD)'].to_s.strip
      return 0 if amount.blank?

      # Remove any non-numeric characters except decimal points
      amount.gsub(/[^\d.]/, '').to_f
    end

  end
end
