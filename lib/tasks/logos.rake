namespace :logos do
    desc "Fetch and save company logos using Clearbit API"
    task fetch: :environment do
      puts "Starting logo fetch process..."
      results = LogoFetcherService.fetch_and_save_logos
      puts "\nProcess completed!"
      puts "Total companies: #{results[:total]}"
      puts "Processed: #{results[:processed]}"
      puts "Successful: #{results[:success]}"
      puts "Errors: #{results[:errors]}"
    end
  end