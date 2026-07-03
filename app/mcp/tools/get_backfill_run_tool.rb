module Mcp
  module Tools
    # Verifiable per-run summary for an async backfill_founded_dates batch. The outcome
    # is derived from each targeted company's persisted state (founded_date presence +
    # founded_year_provenance) rather than a mutable counter, so it is race-free even
    # though the individual backfill jobs run concurrently. A company counts toward this
    # run only once its provenance.attempted_at is at/after the run's started_at; until
    # then it is "pending" (job not run yet).
    class GetBackfillRunTool < BaseTool
      tool_name "get_backfill_run"
      title "Get founded-date backfill run"
      description "Fetch the outcome of an async backfill_founded_dates batch by its run_id. Poll after backfill_founded_dates: status is running while jobs work, then succeeded once every targeted company has been attempted. Returns per-run counts { filled, no_source, no_year, error, pending } plus totals, so \"how many filled vs no-source this run\" is a one-call answer instead of inferring it from get_stats deltas."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Get founded-date backfill run")
      input_schema(
        properties: {
          run_id: { type: "integer", description: "The run_id returned by backfill_founded_dates." }
        },
        required: ["run_id"]
      )

      def self.call(server_context:, run_id:)
        run = PipelineRun.find_by(id: run_id, run_type: BackfillFoundedDatesTool::RUN_TYPE)
        return not_found("Backfill run #{run_id} not found") unless run

        details = run.details || {}
        company_ids = Array(details["company_ids"]).map(&:to_i)
        started = run.started_at || run.created_at
        companies = Company.where(id: company_ids).index_by(&:id)

        counts = Hash.new(0)
        company_ids.each { |id| counts[outcome_for(companies[id], started)] += 1 }

        pending = counts["pending"]
        done = company_ids.size - pending
        status = pending.positive? ? "running" : "succeeded"

        payload = {
          "run_id" => run.id,
          "status" => status,
          "result" => status,
          "targeted" => details["targeted"] == true,
          "created_at" => run.created_at.iso8601,
          "started_at" => started&.iso8601,
          "enqueued" => company_ids.size,
          "attempted" => done,
          "pending" => pending,
          "filled" => counts["filled"],
          "no_source" => counts["no_source"],
          "no_year" => counts["no_year"],
          "error" => counts["error"],
          "missing" => counts["missing"]
        }
        payload["poll"] = "Still running; call get_backfill_run(#{run.id}) again in a few seconds." if pending.positive?

        json_response(payload)
      end

      # Classifies one company against this run: pending until it has been attempted at/after
      # the run started; then filled (a year landed) or the recorded miss status.
      def self.outcome_for(company, started)
        return "missing" if company.nil?

        provenance = company.founded_year_provenance.is_a?(Hash) ? company.founded_year_provenance : {}
        attempted_at = parse_time(provenance["attempted_at"])
        return "pending" if attempted_at.nil? || (started.present? && attempted_at < started)
        return "filled" if company.founded_date.present?

        provenance["status"].presence || "no_source"
      end

      def self.parse_time(value)
        value.present? ? Time.iso8601(value.to_s) : nil
      rescue ArgumentError
        nil
      end
    end
  end
end
