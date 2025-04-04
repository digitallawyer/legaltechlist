require 'httparty'
require 'open-uri'
require 'aws-sdk-s3'
require 'active_storage'

class LogoFetcherService
  include HTTParty
  base_uri 'https://company.clearbit.com/v1/domains'

  def self.fetch_and_save_logos
    # Keep track of API calls and results
    total = Company.where(visible: true).count
    processed = 0
    success = 0
    errors = 0

    Company.where(visible: true).find_each do |company|
      processed += 1
      puts "Processing #{company.name} (#{processed}/#{total})"

      begin
        # Skip if company already has a logo
        if company.logo_url.present?
          puts "- Already has logo, skipping"
          next
        end

        # Try to get domain info from Clearbit
        domain_info = find_domain(company.name)
        next unless domain_info

        # Get logo URL from response
        logo_url = domain_info['logo']
        next unless logo_url

        # Generate filename
        filename = "#{company.id}-#{Time.now.to_i}.png"
        
        if Rails.env.production?
          # Upload to S3/Bucketeer
          s3_url = upload_to_s3(logo_url, filename)
          company.update(logo_url: s3_url)
        else
          # Save locally in development
          logos_dir = Rails.root.join('public', 'logos')
          FileUtils.mkdir_p(logos_dir)
          file_path = logos_dir.join(filename)
          local_url = download_image(logo_url, file_path)
          company.update(logo_url: local_url)
        end

        success += 1
        puts "- Logo saved successfully"

        # Sleep to respect rate limits
        sleep(1)

      rescue => e
        errors += 1
        Rails.logger.error("Error processing #{company.name}: #{e.message}")
        puts "- Error: #{e.message}"
      end
    end

    # Return statistics
    {
      total: total,
      processed: processed,
      success: success,
      errors: errors
    }
  end

  private

  def self.find_domain(company_name)
    options = {
      basic_auth: { username: ENV['CLEARBIT_API_KEY'], password: '' },
      query: { name: company_name }
    }

    response = get("/find", options)
    if response.success?
      response.parsed_response
    else
      Rails.logger.error("Clearbit API Error for #{company_name}: #{response.body}")
      nil
    end
  end

  def self.upload_to_s3(url, filename)
    begin
      downloaded_image = URI.open(url)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: downloaded_image,
        filename: filename,
        content_type: 'image/png'
      )
      
      # Return the URL
      Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: true)
    rescue => e
      Rails.logger.error("Logo upload error for #{filename}: #{e.message}")
      raise e
    end
  end

  def self.download_image(url, file_path)
    URI.open(url) do |image|
      File.open(file_path, 'wb') do |file|
        file.write(image.read)
      end
    end
    
    # Return the full URL including host in development
    if Rails.env.development?
      "#{ENV['APP_HOST']}/logos/#{File.basename(file_path)}"
    else
      "/logos/#{File.basename(file_path)}"
    end
  end
end
