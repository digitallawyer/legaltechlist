class CompanyReviewMarkService
  DECISIONS = %w[verified needs_work reject return_to_contributor].freeze

  # A record that is potentially valid but incomplete should not have to be rejected to
  # get off the reviewer's desk. "return_to_contributor" parks it with the reviewer's
  # instructions attached and the next action belonging to the submitter, distinct from
  # "needs_work" (which the reviewer will pick up again themselves) and from "reject"
  # (which is a verdict that the record does not belong in the index).
  RETURNED_STATUS = "awaiting_contributor".freeze

  def self.call(company:, decision:, admin_user: nil, instructions: nil, fields: nil)
    new(company: company, decision: decision, admin_user: admin_user, instructions: instructions, fields: fields).call
  end

  def initialize(company:, decision:, admin_user: nil, instructions: nil, fields: nil)
    @company = company
    @decision = decision.to_s
    @admin_user = admin_user
    @instructions = instructions.to_s.strip
    @fields = Array(fields).map(&:to_s).reject(&:blank?)
  end

  def call
    raise ArgumentError, "Unknown review decision: #{decision}" unless DECISIONS.include?(decision)

    case decision
    when "verified"
      company.update!(
        quality_status: "verified",
        verification_verdict: "human_confirmed",
        human_reviewed_at: Time.current,
        quality_reviewed_at: Time.current,
        verified_at: company.verified_at || Time.current
      )
    when "needs_work"
      company.update!(
        quality_status: "needs_review",
        verification_verdict: "needs_human_review",
        human_reviewed_at: Time.current,
        quality_reviewed_at: Time.current
      )
    when "reject"
      company.update!(
        quality_status: "rejected",
        verification_verdict: "human_rejected",
        visible: false,
        human_reviewed_at: Time.current,
        quality_reviewed_at: Time.current
      )
    when "return_to_contributor"
      return_to_contributor!
    end

    company
  end

  private

  attr_reader :company, :decision, :admin_user, :instructions, :fields

  def return_to_contributor!
    raise ArgumentError, "Say what the contributor needs to correct or provide." if instructions.blank?
    raise ArgumentError, "A rejected record cannot be returned to its contributor. Reopen it first." if company.quality_status == "rejected"

    request = {
      "requested_at" => Time.current.utc.iso8601,
      "requested_by" => admin_user&.email,
      "instructions" => instructions,
      "fields" => fields,
      "contributor_email" => contributor_email,
      "state" => "awaiting_contributor"
    }

    company.update!(
      quality_status: RETURNED_STATUS,
      verification_verdict: "awaiting_contributor_update",
      # Taken off the public site while it is known to be incomplete, but never deleted.
      visible: false,
      human_reviewed_at: Time.current,
      quality_reviewed_at: Time.current,
      # History is appended, never replaced, so earlier rounds stay readable.
      quality_review: append_history(request)
    )
  end

  def append_history(request)
    existing = company.quality_review.is_a?(Hash) ? company.quality_review.deep_dup : {}
    existing["contributor_requests"] = Array(existing["contributor_requests"]) + [request]
    existing["current_contributor_request"] = request
    existing
  end

  # Company rows carry no submitter of their own, so the contributor is whoever filed
  # the proposal this entry was created from.
  def contributor_email
    CompanyProposal.where(company_id: company.id).where.not(submitter_email: [nil, ""])
                   .order(created_at: :asc).limit(1).pick(:submitter_email)
  end
end
