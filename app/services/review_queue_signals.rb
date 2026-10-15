# Keeps the review queue's stored duplicate and readiness answers current, so the
# overview can read them instead of recomputing both for every open proposal on every
# page view. That recomputation is an identity match against the whole index plus a
# full quality report per proposal: at 182 open proposals it measured ~44s in
# production, past Heroku's 30s router limit, and /admin/proposals stopped loading.
#
# The overview reads what is stored and refreshes only rows that are stale, a bounded
# number per request; a recurring job (config/recurring.yml) refreshes the rest. The
# detail page and every approval gate still resolve live, so a stale overview can
# misplace a row for at most FRESH_FOR but can never let a duplicate through.
class ReviewQueueSignals
  FRESH_FOR = 15.minutes
  LIVE_REFRESH_LIMIT = 20

  def self.refresh!(scope: CompanyProposal.pending_review, limit: nil)
    stale = scope.to_a.select { |proposal| stale?(proposal) }
    stale = stale.sort_by { |proposal| checked_at(proposal) || Time.zone.at(0) }
    stale = stale.first(limit) if limit
    stale.each { |proposal| refresh_one!(proposal) }
    stale.size
  end

  def self.refresh_one!(proposal)
    proposal.persist_duplicate_signals!
    report = CompanyProposalQualityService.call(proposal)
    proposal.update_columns(agent_details: (proposal.agent_details || {}).merge("quality" => report))
  end

  # Stale when either stored answer is missing or older than FRESH_FOR.
  def self.stale?(proposal)
    at = checked_at(proposal)
    at.nil? || at < FRESH_FOR.ago
  end

  def self.checked_at(proposal)
    stamps = [
      proposal.duplicate_signals.is_a?(Hash) ? proposal.duplicate_signals["checked_at"] : nil,
      proposal.cached_quality_report&.dig("checked_at")
    ]
    return nil if stamps.any?(&:blank?)

    stamps.map { |stamp| Time.zone.parse(stamp.to_s) }.min
  rescue ArgumentError
    nil
  end

  def self.blocking?(proposal)
    proposal.duplicate_signals.is_a?(Hash) && proposal.duplicate_signals["blocking"] == true
  end

  def self.ready?(proposal)
    proposal.cached_quality_report&.dig("publish_ready") == true
  end
end
