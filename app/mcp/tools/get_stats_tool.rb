module Mcp
  module Tools
    class GetStatsTool < BaseTool
      tool_name "get_stats"
      title "Get stats"
      description "Read-only directory and backlog metrics for cadence planning and prioritization: company totals and data-quality gaps, breakdowns by_category / by_country / url_health / founded_date, proposal counts by status and type, pipeline run counts, and the current curator autonomy settings. Company metrics are cached (~10 min); pass fresh:true to bypass the cache and recompute (use after a remediation pass to verify before/after counts). Enumerate the exact company_id sets behind these gaps with list_companies, and the flagged pairs with list_duplicate_candidates."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Get stats")
      input_schema(
        properties: {
          fresh: { type: "boolean", description: "Bypass the ~10-min cache and recompute now. Use to verify counts immediately after a remediation pass." }
        },
        required: []
      )

      def self.call(server_context:, fresh: false)
        metrics = AdminDashboardMetrics.load(fresh: fresh)
        summary = (metrics[:company_summary_counts] || {})

        json_response(
          "server_version" => Mcp::CuratorServer::VERSION,
          "fresh" => !!fresh,
          "companies" => {
            "total" => summary[:total],
            "visible" => summary[:visible],
            "hidden" => summary[:hidden],
            "needs_review" => summary[:needs_review],
            "not_reviewed" => summary[:not_reviewed],
            "missing_url" => summary[:missing_url],
            "missing_founded_date" => summary[:missing_founded_date],
            "weak_description" => summary[:weak_description],
            "unknown_taxonomy" => summary[:unknown_taxonomy],
            "broken_url" => summary[:broken_url],
            "acquired" => summary[:acquired],
            "inactive" => summary[:inactive],
            "closed" => summary[:closed],
            "by_status" => summary[:by_status],
            "by_category" => summary[:by_category],
            "by_country" => summary[:by_country],
            "url_health" => summary[:url_health],
            "founded_date" => summary[:founded_date],
            "duplicate_domain_candidates" => summary[:duplicate_domain],
            "duplicate_name_candidates" => summary[:duplicate_name]
          },
          "proposals" => {
            "by_status" => CompanyProposal.group(:status).count,
            "by_type" => CompanyProposal.group(:proposal_type).count,
            "pending_review" => CompanyProposal.pending_review.count
          },
          "pipeline_runs" => {
            "total" => metrics[:pipeline_run_count],
            "failed" => metrics[:failed_pipeline_run_count]
          },
          "curator" => {
            "autopublish_enabled" => Mcp::CuratorPolicy.autopublish_enabled?,
            "autoapply_updates_enabled" => Mcp::CuratorPolicy.autoapply_updates_enabled?,
            "min_confidence" => Mcp::CuratorPolicy.min_confidence,
            "published_today" => Mcp::CuratorPolicy.published_today(curator),
            "remaining_daily_publish_budget" => Mcp::CuratorPolicy.remaining_daily_publish_budget(curator)
          }
        )
      end
    end
  end
end
