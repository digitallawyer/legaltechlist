module Mcp
  module Tools
    # Enqueues asynchronous, server-side founded_date backfills across companies
    # whose founded_date is blank. Each job runs the same cite-only + same-entity
    # guards as proposal enrichment and only writes a year a real source states.
    class BackfillFoundedDatesTool < BaseTool
      RUN_TYPE = "founded_date_backfill_batch".freeze

      tool_name "backfill_founded_dates"
      title "Backfill founded_date on companies"
      description "Enqueue asynchronous server-side founded_date backfills. Each job runs a targeted founding-year web search with the same cite-only + same-entity guards as proposal enrichment and only writes a year a real source states. A blind run (limit) selects only companies that are still blank AND have not been attempted in the last ~3 days, so re-runs reach untried companies instead of re-researching known no-source ones. Pass company_ids to target specific companies (e.g. newly-published ones), which bypasses the cooldown. Returns a run_id; poll get_backfill_run(run_id) for a verifiable per-run summary (filled / no_source / no_year / error / pending counts), or get_company for a single result."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Backfill founded_date on companies")
      input_schema(
        properties: {
          limit: { type: "integer", description: "Blind-sweep size (1-50, default 10). Ignored when company_ids is given. Only picks companies not attempted within the ~3-day cooldown." },
          company_ids: { type: "array", items: { type: "integer" }, description: "Optional: target these specific company ids (still limited to those with a blank founded_date). Bypasses the re-attempt cooldown for explicit targeting." }
        },
        required: []
      )

      def self.call(server_context:, limit: 10, company_ids: nil)
        targeted = Array(company_ids).map(&:to_i).reject(&:zero?)

        if targeted.any?
          selected = Company.missing_founded_date.where(id: targeted).pluck(:id)
          force = true
        else
          capped = [[limit.to_i, 1].max, 50].min
          selected = Company.founded_date_backfill_due(CompanyFoundedDateBackfillService::RE_ATTEMPT_COOLDOWN).order(:id).limit(capped).pluck(:id)
          force = false
        end

        # Create the batch run BEFORE enqueuing so its started_at precedes every job's
        # attempt timestamp; get_backfill_run derives the outcome by comparing each
        # company's persisted provenance.attempted_at against this run's started_at
        # (race-free — no shared counter the concurrent jobs would have to increment).
        run = PipelineRun.create!(
          name: "Founded-date backfill batch",
          run_type: RUN_TYPE,
          status: (selected.any? ? "running" : "succeeded"),
          agent_name: "ClaudeTagCurator",
          records_processed: selected.size,
          started_at: Time.current,
          finished_at: (selected.any? ? nil : Time.current),
          details: { "company_ids" => selected, "enqueued" => selected.size, "targeted" => targeted.any? }
        )

        selected.each { |id| BackfillFoundedDateJob.perform_later(id, curator.id, force) }

        audit!(action: "backfill_founded_dates", summary: "Enqueued #{selected.size} founded_date backfills#{' (targeted)' if targeted.any?}", records_processed: selected.size, details: { "run_id" => run.id, "company_ids" => selected, "targeted" => targeted.any? })

        json_response("result" => "enqueued", "run_id" => run.id, "enqueued" => selected.size, "company_ids" => selected, "targeted" => targeted.any?, "cooldown_days" => (CompanyFoundedDateBackfillService::RE_ATTEMPT_COOLDOWN / 1.day).to_i, "poll" => "Call get_backfill_run(#{run.id}) for the filled / no_source / error run-summary.")
      end
    end
  end
end
