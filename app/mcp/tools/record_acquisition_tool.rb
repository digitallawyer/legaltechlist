module Mcp
  module Tools
    # Records an acquisition on an existing company in one audited call: sets the
    # lifecycle status to "acquired", captures the acquirer (as a free-text name +
    # optional URL, so buyers outside the index are still tracked), links an in-DB
    # successor company when the acquirer/successor is itself listed, and records the
    # exit date. Entries are kept (never deleted) — this is a historical academic record.
    class RecordAcquisitionTool < BaseTool
      tool_name "record_acquisition"
      title "Record an acquisition"
      description "Mark a company as acquired and record its acquirer. Sets status=acquired, stores acquirer_name (and acquirer_url when known), records the exit/acquisition date, and links a successor company when the acquirer is itself in the index (pass successor_slug). The acquirer does NOT need to be in the directory — acquirer_name is free text (e.g. 'LawVu'). Companies are retained as historical records, not deleted."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, title: "Record an acquisition")
      input_schema(
        properties: {
          slug: { type: "string", description: "Slug or numeric id of the acquired company." },
          acquirer_name: { type: "string", description: "Name of the acquiring company (free text; e.g. 'LawVu'). Required." },
          acquirer_url: { type: "string", description: "Acquirer's website (http(s)), when known." },
          acquired_on: { type: "string", description: "Acquisition/exit date as YYYY or YYYY-MM-DD, when known." },
          successor_slug: { type: "string", description: "Optional: slug or id of the acquirer's own TechIndex entry, to link it as the successor record." },
          source_url: { type: "string", description: "Optional citation URL for the acquisition announcement." }
        },
        required: %w[slug acquirer_name]
      )

      def self.call(server_context:, slug:, acquirer_name:, acquirer_url: nil, acquired_on: nil, successor_slug: nil, source_url: nil)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        successor = nil
        if successor_slug.present?
          successor = find_company(successor_slug)
          return not_found("Successor '#{successor_slug}' not found") unless successor
        end

        result = CompanyAcquisitionService.call(
          company: company,
          acquirer_name: acquirer_name,
          acquirer_url: acquirer_url,
          acquired_on: acquired_on,
          successor: successor,
          source_url: source_url
        )
        applied = result.applied

        audit!(action: "record_acquisition", summary: "#{company.name} acquired by #{applied['acquirer_name']}", records_processed: 1, details: { "company_id" => company.id, "applied" => applied })

        json_response(
          "result" => "recorded",
          "company_id" => company.id,
          "company_slug" => company.slug,
          "acquirer" => { "name" => applied["acquirer_name"], "url" => applied["acquirer_url"], "successor_company_id" => applied["successor_company_id"], "successor_slug" => applied["successor_slug"] },
          "acquired_on" => applied["acquired_on"],
          "date_precision" => applied["date_precision"],
          "source_url" => applied["source_url"],
          "company" => company_summary(company)
        )
      rescue ArgumentError => e
        error_response("result" => "blocked", "retryable" => false, "error" => e.message)
      rescue ActiveRecord::RecordInvalid => e
        error_response("result" => "blocked", "retryable" => false, "error" => e.message)
      rescue StandardError => e
        Rails.logger.debug("[RecordAcquisitionTool] transient failure for #{slug}: #{e.class}: #{e.message}")
        error_response("result" => "error", "retryable" => true, "error" => "Transient failure (#{e.class}); safe to retry: #{e.message}")
      end
    end
  end
end
