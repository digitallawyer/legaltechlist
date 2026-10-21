module Mcp
  module Tools
    # Records a funding round on an existing company, with its source. Funding was the one
    # fact the curator could find (a funding announcement is news) but had nowhere to put:
    # a round ended up as an untitled proposal waiting for a person. Cite-only, like a
    # founding year: no source_url, no write. Everything is appended to the record's
    # history, never replaced.
    class RecordFundingTool < BaseTool
      STATUSES = %w[Operating Seed] + ["Early Stage Venture", "Late Stage Venture", "Private Equity", "M&A"]

      tool_name "record_funding"
      title "Record a funding round"
      description "Record a funding round on an existing company. Requires source_url (the announcement or filing: never record a round without one). Give round_amount_usd for the round (it is added to the recorded total and counted as a round), or total_funding_amount_usd when the source states the total raised to date; convert other currencies to USD and say so in reason. funding_status moves the company's stage (#{STATUSES.join(', ')}). Appended to the company's funding history; to correct a wrong figure, record the right total with a source and say what it replaces."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Record a funding round")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." },
          round: { type: "string", description: "Round label as announced, e.g. 'pre-seed', 'Series A'." },
          round_amount_usd: { type: "number", description: "Amount of this round in USD. Added to the recorded total and counted as a round." },
          total_funding_amount_usd: { type: "number", description: "Total raised to date in USD, when the source states it. Replaces the recorded total." },
          announced_on: { type: "string", description: "Announcement date, YYYY-MM-DD or YYYY-MM." },
          funding_status: { type: "string", enum: STATUSES, description: "The company's stage after this round." },
          source_url: { type: "string", description: "Required. The announcement, filing or news article." },
          reason: { type: "string", description: "Anything the reader needs: a currency conversion, a correction." }
        },
        required: %w[slug source_url]
      )

      def self.call(server_context:, slug:, source_url: nil, round: nil, round_amount_usd: nil, total_funding_amount_usd: nil, announced_on: nil, funding_status: nil, reason: nil)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company
        return error_response("result" => "blocked", "retryable" => false, "error" => "source_url must be an http(s) URL: a round is never recorded without its source.") unless Company.valid_http_url?(source_url)
        return error_response("result" => "blocked", "retryable" => false, "error" => "Give round_amount_usd or total_funding_amount_usd.") if round_amount_usd.blank? && total_funding_amount_usd.blank?
        return error_response("result" => "blocked", "retryable" => false, "error" => "funding_status must be one of: #{STATUSES.join(', ')}.") if funding_status.present? && !STATUSES.include?(funding_status)

        amount = BigDecimal(round_amount_usd.to_s) if round_amount_usd.present?
        total = BigDecimal(total_funding_amount_usd.to_s) if total_funding_amount_usd.present?
        return error_response("result" => "blocked", "retryable" => false, "error" => "Amounts must be positive USD figures.") if [amount, total].compact.any? { |value| value <= 0 }

        previous = company.slice(:total_funding_amount_usd, :number_of_funding_rounds, :funding_status)
        new_total = total || (company.total_funding_amount_usd.to_d + amount)
        rounds = amount ? company.number_of_funding_rounds.to_i + 1 : company.number_of_funding_rounds
        review = company.quality_review.is_a?(Hash) ? company.quality_review.deep_dup : {}
        review["funding_events"] = Array(review["funding_events"]) + [{
          "at" => Time.current.utc.iso8601, "round" => round, "round_amount_usd" => amount&.to_f, "total_funding_amount_usd" => new_total.to_f,
          "announced_on" => announced_on, "source_url" => source_url, "reason" => reason, "by" => Mcp::Current.operator_email
        }.compact]
        company.update!({ total_funding_amount_usd: new_total, number_of_funding_rounds: rounds, quality_review: review }.merge(funding_status.present? ? { funding_status: funding_status } : {}))
        audit!(action: "record_funding", summary: "Recorded funding for #{company.name}", records_processed: 1, details: { "company_id" => company.id, "previous" => previous, "source_url" => source_url })

        json_response("result" => "recorded", "company_slug" => company.slug, "total_funding_amount_usd" => company.total_funding_amount_usd.to_f, "number_of_funding_rounds" => company.number_of_funding_rounds,
                      "funding_status" => company.funding_status, "previous" => previous.transform_values { |v| v.is_a?(BigDecimal) ? v.to_f : v }, "source_url" => source_url)
      rescue ActiveRecord::RecordInvalid => e
        error_response("result" => "blocked", "retryable" => false, "error" => e.message)
      end
    end
  end
end
