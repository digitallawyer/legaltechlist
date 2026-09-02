module Mcp
  module Tools
    class GetCompanyTool < BaseTool
      tool_name "get_company"
      title "Get company"
      description "Fetch a single company profile (by slug or id) with taxonomy, funding, quality signals, duplicate matches, and founded_date backfill provenance (status/attempted_at/source_url) so a curator can tell attempted-no-source from untried and see the citation for a filled year."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Get company")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." }
        },
        required: ["slug"]
      )

      def self.call(server_context:, slug:)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        name_dupes = Company.duplicates_by_normalized_name_for(company).limit(10).map { |c| { "id" => c.id, "name" => c.name, "slug" => c.slug } }
        domain_dupes = Company.duplicates_by_domain_for(company).first(10).map { |c| { "id" => c.id, "name" => c.name, "slug" => c.slug } }

        json_response(
          company_summary(company).merge(
            "description" => company.description,
            "revenue_models" => company.revenue_model_names,
            "target_clients" => company.audience_names,
            "tags" => company.tags.map(&:name),
            "total_funding_amount_usd" => company.total_funding_amount_usd,
            "funding_status" => company.funding_status,
            "crunchbase_url" => company.crunchbase_url,
            "linkedin_url" => company.linkedin_url,
            "legalio_url" => company.legalio_url,
            "canonical_domain" => company.canonical_domain.presence || company.canonical_main_domain,
            "founded_year_provenance" => company.founded_year_provenance,
            "founded_date_backfill_status" => founded_date_backfill_status(company),
            "acquisition" => acquisition_details(company),
            "country" => company.country,
          "city" => company.city,
          "automation" => {
            "do_not_enrich" => company.quality_review.is_a?(Hash) && company.quality_review["do_not_enrich"] == true,
            "description_locked" => company.quality_review.is_a?(Hash) && company.quality_review["description_locked"] == true,
            "flag_reasons" => company.quality_review.is_a?(Hash) ? company.quality_review.slice("do_not_enrich_reason", "description_locked_reason") : {}
          },
          "field_edits" => company.quality_review.is_a?(Hash) ? Array(company.quality_review["field_edits"]).last(5).reverse : [],
          "url_health" => url_health_details(company),
            "duplicate_name_matches" => name_dupes,
            "duplicate_domain_matches" => domain_dupes
          )
        )
      end

      # Unambiguous founded_date lifecycle for callers: "filled" (a year is set),
      # an attempt status ("no_source"/"no_year"/"error") when a backfill ran but found
      # nothing, or "untried" when no backfill has been attempted yet.
      def self.founded_date_backfill_status(company)
        return "filled" if company.founded_date.present?

        company.founded_year_provenance&.dig("status").presence || "untried"
      end

      # Acquisition provenance for acquired entries (or any entry carrying acquirer
      # data), so a curator can see the acquirer and successor link.
      def self.acquisition_details(company)
        return nil unless company.acquired? || company.acquirer_name.present? || company.successor_company.present?

        details = company.acquisition_details.is_a?(Hash) ? company.acquisition_details : {}
        {
          "acquirer_name" => company.acquirer_name.presence || company.successor_company&.name,
          "acquirer_url" => company.acquirer_url.presence,
          # acquired_on mirrors the record_acquisition input field name (backed by the
          # exit_date column); date_precision distinguishes a year-only value from a full date.
          "acquired_on" => company.exit_date&.iso8601,
          "date_precision" => details["date_precision"],
          "source_url" => details["source_url"],
          "successor" => (company.successor_company && { "id" => company.successor_company.id, "slug" => company.successor_company.slug, "name" => company.successor_company.name })
        }.compact
      end

      # URL-health signal (soft indicator of possible inactivity). "untried" until a
      # check has run; otherwise the coarse verdict plus consecutive-failure count.
      def self.url_health_details(company)
        return { "status" => "untried" } if company.url_checked_at.blank?

        {
          "status" => company.url_status,
          "status_code" => company.url_status_code,
          # Machine-readable cause (bot_blocked / dns_failure / timeout / http_404 / ...)
          # so an "unknown" verdict can be triaged as "blocks crawlers" vs "actually dead".
          "reason_code" => CompanyUrlHealthCheckService.reason_code_for(company),
          "checked_at" => company.url_checked_at&.iso8601,
          "consecutive_failures" => company.url_consecutive_failures,
          "final_url" => company.url_health&.dig("final_url"),
          "reason" => company.url_health&.dig("reason")
        }.compact
      end
    end
  end
end
