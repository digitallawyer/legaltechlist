# The old scope pass hid out-of-scope records AND set them inactive, which counted live
# law firms as closures in the inactive stat. Records it hid that still answer at their
# own URL get their status back; the hide itself is untouched. Rows with a broken or
# unknown URL, or a human rejection, are left for a curator to judge.
class OutOfScopeStatusRestorer
  REASON = "Out of scope, not defunct: the scope pass set inactive when hiding; url_health is ok.".freeze

  def self.scope
    Company.where(visible: false, status: "inactive", verification_verdict: "out_of_scope_review", url_status: Company::URL_STATUS_OK)
  end

  def self.call(dry_run: true)
    ids = scope.pluck(:id)
    return ids if dry_run

    scope.find_each do |company|
      review = company.quality_review.is_a?(Hash) ? company.quality_review.deep_dup : {}
      review["field_edits"] = Array(review["field_edits"]) + [{
        "at" => Time.current.utc.iso8601,
        "via" => "lifecycle:restore_out_of_scope_status",
        "reason" => REASON,
        "changes" => { "status" => { "from" => "inactive", "to" => "active" } }
      }]
      company.update_columns(status: "active", quality_review: review, updated_at: Time.current)
    end
    ids
  end
end
