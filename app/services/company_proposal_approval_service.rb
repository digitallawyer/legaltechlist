class CompanyProposalApprovalService
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:, admin_user:, duplicate_override: false, publish: false)
    @proposal = proposal
    @admin_user = admin_user
    @duplicate_override = duplicate_override
    @publish = publish
  end

  def call
    raise ArgumentError, "Rejected proposals cannot be approved" if proposal.rejected?
    # Idempotent recovery: if this proposal already minted a company, don't try to
    # create a second one. Promote the existing invisible draft to visible when a
    # publish is requested; otherwise return the existing record unchanged.
    return promote_existing_company if proposal.company_id.present?

    ensure_description!
    validate_proposal!

    guard_against_existing_company!

    company = Company.new(company_attributes)
    company.visible = publish
    company.quality_status = "needs_review"
    company.verification_verdict = "human_approved_candidate"
    company.human_reviewed_at = Time.current
    company.quality_reviewed_at = Time.current
    company.canonical_domain = company.canonical_main_domain
    company.fingerprint = company.calculated_fingerprint
    company.save!

    revenue_model_ids = Array(proposal.final_changes["business_model_ids"]).map(&:presence).compact
    if revenue_model_ids.empty? && proposal.final_changes["business_model_id"].present?
      revenue_model_ids = [proposal.final_changes["business_model_id"]]
    end
    company.business_model_ids = revenue_model_ids if revenue_model_ids.any?

    target_client_ids = Array(proposal.final_changes["target_client_ids"]).map(&:presence).compact
    company.target_client_ids = target_client_ids if target_client_ids.any?

    if proposal.final_changes["all_tags"].present?
      company.all_tags = proposal.final_changes["all_tags"]
      company.save!
    end

    proposal.update!(
      status: publish ? "published" : "approved_to_draft",
      company: company,
      admin_user: admin_user,
      reviewed_at: Time.current,
      approved_at: Time.current
    )

    company
  end

  private

  attr_reader :proposal, :admin_user, :duplicate_override, :publish

  # Publish an already-created draft (or no-op if already visible). Publishing is
  # still the sensitive action, so it re-checks duplicate and publish blockers.
  def promote_existing_company
    company = proposal.company

    if publish && !company.visible?
      validate_proposal!
      company.update!(visible: true)
      proposal.update!(status: "published", admin_user: admin_user, reviewed_at: Time.current, approved_at: Time.current)
    end

    company
  end

  # Duplicate state is resolved against the index and the open queue as they are now,
  # not as they were when the proposal was created. The message names the match so the
  # operator can act on it without going hunting.
  def validate_proposal!
    # Force a fresh resolution rather than reusing anything computed earlier in this
    # process: approval is the moment the answer has to be current, and a sibling
    # proposal may have been resolved (or created) since it was last looked at.
    signals = proposal.current_duplicate_signals(refresh: true)
    if signals["blocking"] && !duplicate_override
      raise ArgumentError, "Resolve the duplicate before approval: #{signals['recommended_action']}"
    end
    raise ArgumentError, "Resolve publish blockers before publication: #{publish_blockers.to_sentence}" if publish && publish_blockers.any?
  end

  # Last line of defence, immediately before the row is written. The duplicate check
  # above works off names and domains; this works off the identity fingerprint the
  # Company table itself uses, and so also catches a concurrent approval of the same
  # company from another session or a batch running beside this one.
  def guard_against_existing_company!
    return if duplicate_override

    fingerprint = Company.new(company_attributes).calculated_fingerprint
    return if fingerprint.blank?

    existing = Company.where(fingerprint: fingerprint).first
    return if existing.nil?

    raise ArgumentError, "#{existing.name} (##{existing.id}) already holds this name and domain. Keep that entry and reject this proposal, or approve with the duplicate override if they are genuinely different companies."
  end

  def publish_blockers
    @publish_blockers ||= CompanyProposalQualityService.call(proposal)["blockers"]
  end

  def company_attributes
    changes = proposal.final_changes.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
    changes.except("source_description").merge(
      "category_id" => blank_to_nil(changes["category_id"]),
      "secondary_category_id" => blank_to_nil(changes["secondary_category_id"] || legacy_secondary_category_id(changes)),
      "business_model_id" => blank_to_nil(changes["business_model_id"]),
      "target_client_id" => blank_to_nil(changes["target_client_id"])
    ).except("sub_category_id")
  end

  def legacy_secondary_category_id(changes)
    return if changes["sub_category_id"].blank?

    sub = SubCategory.find_by(id: changes["sub_category_id"])
    Category.find_by(name: sub&.name)&.id
  end

  def blank_to_nil(value)
    value.presence
  end

  def ensure_description!
    return if proposal.final_changes["description"].present?

    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_user)
    proposal.reload
  end
end
