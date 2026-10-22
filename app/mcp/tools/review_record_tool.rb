module Mcp
  module Tools
    # Judge one existing company from what the server reads on its own website. It is the
    # evidence-first replacement for hand-reading a site: the server fetches (and remembers)
    # the pages, a toolless model decides scope and writes the entry from them, and the entry
    # is only offered when quotes from the pages support it. It changes nothing.
    class ReviewRecordTool < BaseTool
      tool_name "review_record"
      title "Review a record from its own site"
      description "Judge an existing company from its own website, as the server read it. Returns decision (list, close, needs_work), scope (in_scope, law_firm, consultancy, not_legal_tech, parked_or_for_sale, unreadable), a grounded `description` (only when decision is list; every claim backed by a quote the server checked against the page), confidence, the evidence the server saw (fetch status, final URL, whether the page renders text) successor_note (the site now belongs to another company) and lifecycle_note (the pages say it closed, was acquired or is winding down: a status to check and record with its source), and whether the answer was reused because the evidence has not changed. When the site cannot be read no model is called and the answer is needs_work with the reason: never invent a description in that case. It changes nothing; apply the result with update_company_field (list) or mark_review (close, with the scope as reason_code and the evidence final_url as source_url). Pass refresh=true to refetch."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, title: "Review record")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." },
          refresh: { type: "boolean", description: "Refetch the site and judge again even if the evidence is unchanged." },
          model: { type: "string", description: "Override the judge model (for comparisons)." }
        },
        required: ["slug"]
      )

      def self.call(server_context:, slug:, refresh: false, model: nil)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        result = RecordJudgeService.call(company: company, refresh: ActiveModel::Type::Boolean.new.cast(refresh), model: model)
        json_response(result.merge("company_slug" => company.slug, "current_description" => company.description))
      end
    end
  end
end
