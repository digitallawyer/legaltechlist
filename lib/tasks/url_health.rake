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

  # Verdicts recorded before offsite_redirect/suspected_hijack existed read "ok" even
  # when the redirect landed elsewhere (Vauban: vauban.io -> mountainpass.tv). Re-probe
  # those so the new codes are assigned. DRY_RUN=true (default) only lists them.
  desc "Re-check companies whose stored final_url left the company's own domain. DRY_RUN=false to enqueue"
  task recheck_offsite: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    ids = Company.where(url_status: Company::URL_STATUS_OK).where("url_health ->> 'final_url' IS NOT NULL").select do |company|
      requested = Company.canonical_domain_for(company.main_url)
      landed = Company.canonical_domain_for(company.url_health["final_url"])
      requested.present? && landed.present? && requested != landed &&
        !landed.end_with?(".#{requested}") && !requested.end_with?(".#{landed}") &&
        requested.split(".").first != landed.split(".").first
    end.map(&:id)

    ids.each { |id| CheckCompanyUrlHealthJob.perform_later(id) } unless dry_run
    puts "#{dry_run ? 'Would enqueue' : 'Enqueued'} #{ids.size} offsite re-checks: #{ids.first(50).join(', ')}#{' ...' if ids.size > 50}"
  end
end
