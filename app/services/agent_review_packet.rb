# Everything a reviewer needs from one agent-review or duplicate-review run, so the
# findings can be rendered wherever the reviewer happens to be.
#
# The results used to be reachable only from their own page, which meant running a
# review threw the reviewer out of the company draft they were working on. Wrapping the
# run in a packet lets the company draft render the same findings inline, and keeps the
# apply rules in one place rather than duplicated per view.
class AgentReviewPacket
  # Bookkeeping fields. Applying them never changes public text.
  METADATA_APPLY_FIELDS = %w[
    quality_status
    verification_verdict
    quality_score
    canonical_domain
    fingerprint
  ].freeze

  # Public-text fields, written only through applicable_description.
  CONTENT_APPLY_FIELDS = %w[description].freeze

  APPLY_FIELDS = (METADATA_APPLY_FIELDS + CONTENT_APPLY_FIELDS).freeze

  # Run types that carry reviewer-facing findings, newest first per company.
  AGENT_REVIEW_TYPES = %w[company_agent_review company_review].freeze
  DUPLICATE_REVIEW_TYPES = %w[duplicate_domain_review].freeze

  def self.latest_agent_review_for(company)
    wrap(PipelineRun.for_company(company).where(run_type: AGENT_REVIEW_TYPES).recent.first)
  end

  def self.latest_duplicate_review_for(company)
    wrap(PipelineRun.for_company(company).where(run_type: DUPLICATE_REVIEW_TYPES).recent.first)
  end

  def self.wrap(pipeline_run)
    pipeline_run && new(pipeline_run)
  end

  def initialize(pipeline_run)
    @pipeline_run = pipeline_run
  end

  attr_reader :pipeline_run

  def id = pipeline_run.id
  def name = pipeline_run.name
  def status = pipeline_run.status
  def created_at = pipeline_run.created_at
  def details = @details ||= pipeline_run.details || {}

  def company = @company ||= Company.find_by(id: details["company_id"])
  def evidence = Array(details["evidence"])
  def tool_results = details["tool_results"] || {}
  def description_draft = details["description_draft"] || {}
  def description_critic = details["description_critic"] || {}
  def review_coordinator = details["review_coordinator"] || {}
  def duplicate_review = details["duplicate_review"] || {}
  def risks = Array(details["risks"])
  def admin_decision = details["admin_decision"]
  def proposed_corrections = details["proposed_corrections"] || details["proposed_changes"] || {}

  def findings? = review_coordinator.present? || description_draft.present? || evidence.any?
  def duplicate_findings? = duplicate_review.present?

  # ---- what an admin may apply from here ---------------------------------

  def applicable_corrections
    resolve_corrections
    @applicable_corrections
  end

  def description_apply_source
    resolve_corrections
    @description_apply_source
  end

  def description_apply_block
    resolve_corrections
    @description_apply_block
  end

  def review_only_corrections
    resolve_corrections
    @review_only_corrections
  end

  private

  # Split the packet's proposed corrections into what an admin can apply (keyed by
  # company attribute) and what stays informational. The description is resolved
  # separately because which string is authorised depends on the critic verdict, and
  # because a blocked description must explain itself rather than silently vanish.
  def resolve_corrections
    return if defined?(@applicable_corrections)

    @applicable_corrections = proposed_corrections.slice(*METADATA_APPLY_FIELDS)
    @description_apply_source = nil
    @description_apply_block = nil

    candidate = applicable_description
    if candidate
      @applicable_corrections["description"] = candidate[:value]
      @description_apply_source = candidate[:source]
    end

    @review_only_corrections = proposed_corrections.except(*METADATA_APPLY_FIELDS, "proposed_description")
    @review_only_corrections["proposed_description"] = proposed_corrections["proposed_description"] if proposed_corrections.key?("proposed_description") && candidate.nil?
  end

  # The description string this packet authorises an admin to publish, or nil with
  # description_apply_block set to the reason. Two gates, both required:
  #
  #   1. The stored critic verdict must name a specific string — the draft when the
  #      critic passed it, the critic's own narrower rewrite when it asked for a
  #      revision. A missing or rejecting verdict authorises nothing.
  #   2. That exact string must then clear the same deterministic description gate the
  #      publish path enforces, computed live. A stored verdict alone is never
  #      sufficient: the packet may predate later prompt or gate changes, and the text
  #      is about to become public.
  def applicable_description
    candidate = critic_authorised_description
    return nil if candidate.nil?

    verdict = CompanyProposalEnrichmentService.description_critic_for(candidate[:value])
    return candidate if verdict["verdict"] == "pass"

    issues = Array(verdict["issues"]).map(&:to_s).map(&:downcase).to_sentence.presence
    @description_apply_block = if issues
      "The #{candidate[:source]} does not clear the publication gate (#{issues}). Edit the company description directly instead."
    else
      "The #{candidate[:source]} does not clear the publication gate. Edit the company description directly instead."
    end
    nil
  end

  def critic_authorised_description
    proposed = proposed_corrections["proposed_description"].to_s.strip
    suggested = description_critic["suggested_revision"].to_s.strip
    verdict = description_critic["verdict"].to_s

    case verdict
    when "pass"
      return { value: proposed, source: "critic-approved draft" } if proposed.present?

      @description_apply_block = "The critic passed this record but no proposed description was recorded."
    when "revise"
      return { value: suggested, source: "critic's suggested revision" } if suggested.present?

      @description_apply_block = "The critic asked for a revision but did not supply replacement text. Revise the description by hand."
    when ""
      @description_apply_block = "No description critic verdict is recorded on this review, so no description can be applied. Re-run the review first." if proposed.present?
    else
      @description_apply_block = "The critic returned #{verdict}, so its draft cannot be published. Revise the description by hand."
    end

    nil
  end
end
