module Mcp
  module Tools
    class MarkReviewTool < BaseTool
      tool_name "mark_review"
      title "Mark company review"
      description "Record a human-style review decision on an existing company: verified, needs_work, reject (hides it: out of scope or not a real company), return_to_contributor, or hide_pending_review (hides it now while the decision stays open, e.g. its website was hijacked). A hidden record is never re-published automatically; marking it verified or needs_work reopens it. Give a reason: it is kept in the review audit."
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true, title: "Mark company review")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." },
          decision: { type: "string", enum: CompanyReviewMarkService::DECISIONS, description: "One of: #{CompanyReviewMarkService::DECISIONS.join(', ')}." },
          reason: { type: "string", description: "Why. Required for reject and hide_pending_review; recorded in the review audit." },
          reason_code: { type: "string", enum: Company::CLOSE_OUT_REASONS, description: "Required for reject. A reject is final: the record is closed out for good, never researched or swept again, and the same domain submitted later is turned away. Use it for a law firm, a consultancy, a hijacked or parked domain, a non-company or spam. Use needs_work or hide_pending_review when the answer is not final." },
          source_url: { type: "string", description: "reject only: the page that shows why (the parked page, the firm's site)." },
          instructions: { type: "string", description: "return_to_contributor only: what the contributor needs to correct or provide." }
        },
        required: ["slug", "decision"]
      )

      REASON_REQUIRED = %w[reject hide_pending_review].freeze

      def self.call(server_context:, slug:, decision:, reason: nil, reason_code: nil, source_url: nil, instructions: nil)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company
        unless CompanyReviewMarkService::DECISIONS.include?(decision.to_s)
          return not_found("Unknown decision '#{decision}'. Use one of: #{CompanyReviewMarkService::DECISIONS.join(', ')}")
        end

        if REASON_REQUIRED.include?(decision.to_s) && reason.to_s.strip.blank?
          return error_response("result" => "blocked", "retryable" => false, "error" => "#{decision} hides a public record and requires a `reason`.")
        end

        if decision.to_s == "reject" && reason_code.to_s.strip.blank?
          return error_response("result" => "blocked", "retryable" => false, "error" => "reject closes a record out for good and requires a `reason_code` (#{Company::CLOSE_OUT_REASONS.join(', ')}).")
        end

        CompanyReviewMarkService.call(company: company, decision: decision.to_s, admin_user: curator,
                                      instructions: instructions, context: { "reason" => reason.to_s.strip.presence, "reason_code" => reason_code.to_s.strip.presence, "source_url" => source_url.to_s.strip.presence, "via" => "mcp", "operator" => Mcp::Current.operator_email }.compact)
        company.reload

        audit!(action: "mark_review", summary: "Marked #{company.name} as #{decision}", records_processed: 1, details: { "company_id" => company.id, "decision" => decision, "reason" => reason })

        json_response(
          "company_slug" => company.slug,
          "decision" => decision,
          "quality_status" => company.quality_status,
          "verification_verdict" => company.verification_verdict,
          "visible" => company.visible
        )
      end
    end
  end
end
