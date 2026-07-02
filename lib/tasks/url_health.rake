namespace :url_health do
  desc "Backfill machine-readable reason_code onto existing url_health rows (no network probes)"
  task backfill_reason_codes: :environment do
    scope = Company.where.not(url_checked_at: nil).where("url_health IS NOT NULL")
    total = scope.count
    updated = 0

    scope.find_each(batch_size: 500) do |company|
      health = company.url_health.is_a?(Hash) ? company.url_health : {}
      next if health["reason_code"].present?

      code = CompanyUrlHealthCheckService.derive_reason_code(
        url_status: company.url_status,
        status_code: company.url_status_code,
        reason: health["reason"]
      )
      company.update_columns(url_health: health.merge("reason_code" => code))
      updated += 1
    end

    puts "url_health reason_code backfill: #{updated} updated of #{total} checked companies."
  end
end
