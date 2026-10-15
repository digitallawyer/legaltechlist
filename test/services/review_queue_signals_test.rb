require "test_helper"

class ReviewQueueSignalsTest < ActiveSupport::TestCase
  def open_proposal(duplicate_signals: {}, quality: nil)
    changes = { "name" => "Queuewise", "main_url" => "https://queuewise.example", "location" => "Lyon, France",
                "description" => "Queuewise builds contract review software for legal teams.", "category_id" => categories(:one).id }
    details = quality ? { "quality" => quality } : {}
    CompanyProposal.create!(status: "ready_for_review", proposal_type: "user_contribution", source: "user_contribution",
                            source_identifier: SecureRandom.uuid, source_payload: {}, proposed_changes: changes,
                            final_changes: changes, duplicate_signals: duplicate_signals, agent_details: details)
  end

  test "a proposal with no stored answers is stale and gets both refreshed" do
    proposal = open_proposal
    assert ReviewQueueSignals.stale?(proposal)

    ReviewQueueSignals.refresh!(scope: CompanyProposal.where(id: proposal.id))
    proposal.reload

    assert proposal.duplicate_signals["checked_at"].present?
    assert proposal.cached_quality_report.present?
    assert_not ReviewQueueSignals.stale?(proposal)
  end

  test "fresh answers are read, not recomputed" do
    now = Time.current.utc.iso8601
    proposal = open_proposal(duplicate_signals: { "blocking" => true, "checked_at" => now },
                             quality: { "publish_ready" => true, "verification_state" => "evidence_backed", "checked_at" => now })

    CompanyProposalQualityService.stub(:call, ->(*) { raise "should not recompute a fresh row" }) do
      assert_equal 0, ReviewQueueSignals.refresh!(scope: CompanyProposal.where(id: proposal.id))
    end
    assert ReviewQueueSignals.blocking?(proposal)
    assert ReviewQueueSignals.ready?(proposal)
  end

  test "a per-request limit refreshes the oldest rows first and leaves the rest for the job" do
    old = open_proposal(duplicate_signals: { "checked_at" => 2.hours.ago.utc.iso8601 },
                        quality: { "verification_state" => "unverified", "checked_at" => 2.hours.ago.utc.iso8601 })
    never = open_proposal

    assert_equal 1, ReviewQueueSignals.refresh!(scope: CompanyProposal.where(id: [old.id, never.id]), limit: 1)
    assert_not ReviewQueueSignals.stale?(never.reload), "never-checked rows go first"
    assert ReviewQueueSignals.stale?(old.reload)
  end
end
