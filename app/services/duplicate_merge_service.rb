# Folds the verified improvements from a duplicate proposal into the record that is
# being kept, then rejects the proposal in favour of it.
#
# Deliberately narrow. It writes only fields DuplicateComparisonService marked
# mergeable, which means: the existing entry has nothing there, the field is not part of
# the entry's identity, and something was actually retrieved for the proposal. A
# populated value is never overwritten because the proposal disagrees with it — that is
# a conflict for a human, not a merge.
class DuplicateMergeService
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:, company:, fields:, admin_user:)
    @proposal = proposal
    @company = company
    @requested_fields = Array(fields).map(&:to_s)
    @admin_user = admin_user
  end

  def call
    comparison = DuplicateComparisonService.call(proposal: proposal, company: company)
    allowed = comparison["mergeable_fields"] & requested_fields
    raise ArgumentError, "None of the selected fields can be merged into #{company.name}." if allowed.empty?

    rows = comparison["rows"].index_by { |row| row["key"] }
    applied = allowed.each_with_object({}) do |field, acc|
      row = rows[field]
      company.public_send("#{field}=", row["proposal_value"])
      acc[field] = { "from" => row["company_value"], "to" => row["proposal_value"], "sources" => row["evidence"] }
    end

    company.save!
    record_merge!(applied)
    reject_proposal!(applied)

    { "company_id" => company.id, "applied" => applied }
  end

  private

  attr_reader :proposal, :company, :requested_fields, :admin_user

  # Provenance for a change to a live public entry: which fields moved, what they were,
  # what they became, and what supported each one.
  def record_merge!(applied)
    PipelineRun.create!(
      name: "Duplicate merge into #{company.name}",
      run_type: "duplicate_merge",
      status: "succeeded",
      agent_name: "DuplicateMergeService",
      records_processed: applied.size,
      details: {
        "company_id" => company.id,
        "proposal_id" => proposal.id,
        "merged_by" => admin_user&.email,
        "merged_at" => Time.current.utc.iso8601,
        "applied_changes" => applied
      }
    )
  end

  # The proposal is resolved, not discarded: it keeps its rejection reason, the entry
  # that was kept, and the list of what it contributed before being closed.
  def reject_proposal!(applied)
    proposal.update!(
      status: "rejected",
      admin_user: admin_user,
      reviewed_at: Time.current,
      rejected_at: Time.current,
      rejection_reason: "Merged #{applied.keys.map(&:humanize).map(&:downcase).to_sentence} into #{company.name} (##{company.id}); that record is canonical.",
      agent_details: proposal.agent_details.merge(
        "canonical_record" => {
          "company_id" => company.id,
          "resolved_by" => admin_user&.email,
          "resolved_at" => Time.current.utc.iso8601,
          "merged_fields" => applied.keys
        }
      )
    )
  end
end
