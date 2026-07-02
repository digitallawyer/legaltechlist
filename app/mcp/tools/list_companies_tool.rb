module Mcp
  module Tools
    # Filtered, paginated enumeration of directory companies so a curator can pull the
    # exact company_id set behind a data-quality gap (null founded_date, weak
    # description, missing URL, broken URL, a category/country, a review state) and feed
    # those ids into batch remediation (backfill_founded_dates, check_url_health, edits).
    class ListCompaniesTool < BaseTool
      MAX_LIMIT = 200
      DEFAULT_LIMIT = 50
      URL_HEALTH_STATES = %w[ok broken unknown untried].freeze
      REVIEW_STATES = %w[not_reviewed in_review verified rejected].freeze
      # Accept the get_stats term "needs_review" as an alias for the review_state value
      # "in_review" so the two tools line up instead of silently returning everything.
      REVIEW_STATE_ALIASES = { "needs_review" => "in_review" }.freeze

      tool_name "list_companies"
      title "List companies"
      description "Enumerate directory companies with filters and offset/limit pagination (limit up to 200), returning each company_id plus core fields and the relevant quality flags. Use it to pull the target id set behind a get_stats gap and drive batch remediation. Filters: category_id, country (canonical English name from get_stats.by_country), review_state (not_reviewed|in_review|verified|rejected), founded_date_null, url_health_status (ok|broken|unknown|untried), weak_description, missing_url, status (active/acquired/inactive/closed), visible, and free-text query. Defaults to ALL companies (visible + hidden) so the counts match get_stats data-quality totals; pass visible:true to restrict to the public index (matching by_category/by_country). Page with offset until has_more is false."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "List companies")
      input_schema(
        properties: {
          category_id: { type: "integer", description: "Only companies in this primary category (id from get_taxonomy / get_stats.by_category)." },
          country: { type: "string", description: "Only companies resolving to this country (canonical English name as shown in get_stats.by_country, e.g. \"Switzerland\")." },
          review_state: { type: "string", enum: %w[not_reviewed in_review verified rejected needs_review], description: "Review state filter: not_reviewed | in_review | verified | rejected. \"needs_review\" is accepted as an alias for in_review (the get_stats term). An unrecognized value returns an error rather than the unfiltered set." },
          founded_date_null: { type: "boolean", description: "Only companies with no founded_date set." },
          url_health_status: { type: "string", enum: %w[ok broken unknown untried], description: "URL-health verdict filter: ok | broken | unknown | untried (never checked). An unrecognized value returns an error." },
          weak_description: { type: "boolean", description: "Only companies with a weak/too-short description." },
          missing_url: { type: "boolean", description: "Only companies with no main_url." },
          status: { type: "string", description: "Lifecycle status filter (e.g. active, acquired, inactive, closed). Case-insensitive." },
          visible: { type: "boolean", description: "Restrict by visibility: true = public index only, false = hidden only. Omit for all companies." },
          query: { type: "string", description: "Free-text match against name/description/location." },
          limit: { type: "integer", description: "Page size (1-200, default 50)." },
          offset: { type: "integer", description: "Rows to skip for pagination (default 0)." }
        },
        required: []
      )

      def self.call(server_context:, category_id: nil, country: nil, review_state: nil, founded_date_null: false,
                    url_health_status: nil, weak_description: false, missing_url: false, status: nil,
                    visible: nil, query: nil, limit: DEFAULT_LIMIT, offset: 0)
        capped = [[limit.to_i, 1].max, MAX_LIMIT].min
        skip = [offset.to_i, 0].max

        resolved_review_state = REVIEW_STATE_ALIASES.fetch(review_state.to_s, review_state.to_s) if review_state.present?
        if review_state.present? && !REVIEW_STATES.include?(resolved_review_state)
          return error_response("error" => "Unknown review_state '#{review_state}'. Accepted values: #{REVIEW_STATES.join(', ')} (or the alias 'needs_review' for in_review).")
        end
        if url_health_status.present? && !URL_HEALTH_STATES.include?(url_health_status.to_s)
          return error_response("error" => "Unknown url_health_status '#{url_health_status}'. Accepted values: #{URL_HEALTH_STATES.join(', ')}.")
        end

        scope = Company.all
        scope = scope.where(visible: visible) unless visible.nil?
        scope = scope.where(category_id: category_id.to_i) if category_id.present?
        scope = scope.with_review_state(resolved_review_state) if review_state.present?
        scope = scope.missing_founded_date if founded_date_null
        scope = scope.weak_description if weak_description
        scope = scope.missing_main_url if missing_url
        scope = scope.where("LOWER(status) = ?", status.to_s.strip.downcase) if status.present?
        scope = apply_url_health(scope, url_health_status)
        scope = scope.text_search(query) if query.present?

        if country.present?
          ids = Company.ids_with_normalized_country(country, scope: scope)
          scope = Company.where(id: ids)
        end

        total = scope.count
        companies = scope.includes(:category, :secondary_category).order(:name).offset(skip).limit(capped)

        json_response(
          "total" => total,
          "offset" => skip,
          "limit" => capped,
          "count" => companies.size,
          "has_more" => (skip + companies.size) < total,
          "filters" => applied_filters(category_id: category_id, country: country, review_state: review_state,
                                        founded_date_null: founded_date_null, url_health_status: url_health_status,
                                        weak_description: weak_description, missing_url: missing_url, status: status,
                                        visible: visible, query: query),
          "companies" => companies.map { |company| company_row(company) }
        )
      end

      def self.apply_url_health(scope, url_health_status)
        case url_health_status.to_s
        when "ok" then scope.where(url_status: Company::URL_STATUS_OK)
        when "broken" then scope.url_broken
        when "unknown" then scope.where(url_status: Company::URL_STATUS_UNKNOWN)
        when "untried" then scope.where(url_checked_at: nil)
        else scope
        end
      end

      def self.company_row(company)
        company_summary(company).merge(
          "review_state" => company.review_state,
          "url_health_status" => company.url_checked_at.blank? ? "untried" : company.url_status,
          "founded_date_backfill_status" => GetCompanyTool.founded_date_backfill_status(company),
          "weak_description" => company.description.to_s.strip.length < 40,
          "country" => company.resolved_country
        )
      end

      def self.applied_filters(**filters)
        filters.reject { |_key, value| value.nil? || value == false }.transform_keys(&:to_s)
      end
    end
  end
end
