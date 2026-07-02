class AdminDashboardMetrics
  CACHE_TTL = 10.minutes

  def self.load(fresh: false)
    Rails.cache.delete(cache_key) if fresh
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { compute }
  end

  def self.cache_key
    "admin/dashboard_metrics/v1/#{Company.duplicate_candidate_cache_version}"
  end

  def self.compute
    duplicate_domain_ids = Company.duplicate_domain_candidate_ids
    duplicate_name_ids = Company.duplicate_name_candidate_ids
    # Lifecycle breakdown keyed by normalized status (nil -> "unknown"). Used for the
    # at-a-glance index-health view (acquired/inactive counts).
    by_status = Company.group(:status).count.transform_keys { |status| status.presence || "unknown" }

    {
      company_count: Company.count,
      missing_url_count: Company.missing_main_url.count,
      weak_description_count: Company.weak_description.count,
      description_review_count: Company.description_review_candidates.count,
      duplicate_domain_count: duplicate_domain_ids.size,
      duplicate_name_count: duplicate_name_ids.size,
      proposal_review_count: CompanyProposal.pending_review.count,
      pipeline_run_count: PipelineRun.count,
      failed_pipeline_run_count: PipelineRun.failed.count,
      duplicate_domain_ids: duplicate_domain_ids,
      duplicate_name_ids: duplicate_name_ids,
      company_summary_counts: {
        total: Company.count,
        visible: Company.where(visible: true).count,
        hidden: Company.where(visible: false).count,
        missing_url: Company.missing_main_url.count,
        missing_founded_date: Company.missing_founded_date.count,
        weak_description: Company.weak_description.count,
        duplicate_domain: duplicate_domain_ids.size,
        duplicate_name: duplicate_name_ids.size,
        broken_url: Company.url_broken.count,
        acquired: by_status["acquired"].to_i,
        # inactive now mirrors by_status["inactive"] exactly (single source of truth);
        # "closed" entries are reported separately rather than folded into inactive.
        inactive: by_status["inactive"].to_i,
        closed: by_status["closed"].to_i,
        by_status: by_status,
        needs_review: Company.needs_review.count,
        not_reviewed: Company.review_state_not_reviewed.count,
        unknown_taxonomy: unknown_taxonomy_count,
        by_category: visible_by_category,
        by_country: visible_by_country,
        url_health: url_health_breakdown,
        founded_date: founded_date_breakdown
      }
    }
  end

  # Visible-company counts per category, including categories with zero visible
  # companies (e.g. "Unknown"), sorted by count descending.
  def self.visible_by_category
    counts = Company.publicly_visible.group(:category_id).count
    rows = Category.order(:name).pluck(:id, :name).map do |id, name|
      { "category_id" => id, "name" => name, "visible_count" => counts[id].to_i }
    end
    uncategorized = counts[nil].to_i
    rows << { "category_id" => nil, "name" => "(uncategorized)", "visible_count" => uncategorized } if uncategorized.positive?
    rows.sort_by { |row| -row["visible_count"] }
  end
  private_class_method :visible_by_category

  # Visible-company counts per resolved+normalized country (complete, uncapped),
  # sorted by count descending. Country is free text with native-language variants,
  # so it is canonicalized in Ruby the same way the statistics pages do.
  def self.visible_by_country
    tally = Hash.new(0)
    Company.publicly_visible.pluck(:country, :location).each do |country, location|
      resolved = country.presence || LocationCountryResolver.country_name_for(location)
      next if resolved.blank?

      tally[LocationCountryResolver.normalize_country_name(resolved)] += 1
    end
    tally.sort_by { |_country, count| -count }.map { |country, count| { "country" => country, "visible_count" => count } }
  end
  private_class_method :visible_by_country

  # URL-health verdict breakdown across the whole directory. "untried" = never
  # checked; last_run_at is the most recent check timestamp.
  def self.url_health_breakdown
    by_status = Company.group(:url_status).count
    {
      "ok" => by_status[Company::URL_STATUS_OK].to_i,
      "broken" => by_status[Company::URL_STATUS_BROKEN].to_i,
      "unknown" => by_status[Company::URL_STATUS_UNKNOWN].to_i,
      "untried" => Company.where(url_checked_at: nil).count,
      "last_run_at" => Company.maximum(:url_checked_at)&.utc&.iso8601
    }
  end
  private_class_method :url_health_breakdown

  # Founded-date coverage across the whole directory, distinguishing "never
  # attempted" (immediately actionable) from "attempted, no source found".
  def self.founded_date_breakdown
    null_scope = Company.missing_founded_date
    null_count = null_scope.count
    no_source = null_scope.where("founded_year_provenance IS NOT NULL AND (founded_year_provenance ->> 'status') IS NOT NULL").count
    {
      "present" => Company.where.not(founded_date: [nil, ""]).count,
      "null" => null_count,
      "backfill_untried" => null_count - no_source,
      "backfill_no_source" => no_source
    }
  end
  private_class_method :founded_date_breakdown

  def self.unknown_taxonomy_count
    Company.left_joins(:category, :business_model, :target_client).where(
      "categories.id IS NULL OR categories.name = :unknown OR business_models.id IS NULL OR business_models.name = :unknown OR target_clients.id IS NULL OR target_clients.name = :unknown",
      unknown: "Unknown"
    ).count
  end
  private_class_method :unknown_taxonomy_count
end
