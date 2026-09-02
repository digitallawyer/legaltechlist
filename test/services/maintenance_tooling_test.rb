require "test_helper"
require "minitest/mock"

# The five failures behind tonight's stalled approvals, each covered so the same wall
# cannot come back silently.
class MaintenanceToolingTest < ActiveSupport::TestCase
  GOOD = "Veronto builds an access-request and trade-secret workflow platform for law firms and in-house legal teams, hosted in the EU.".freeze

  setup do
    @admin = admin_users(:one)
    @company = companies(:one)
    @company.update!(name: "Veronto", main_url: "https://veronto.example", description: "An enrichment overwrote the original text.")
    @company.update_columns(quality_status: nil, quality_review: nil, fingerprint: @company.calculated_fingerprint)
    @context = { admin_user: @admin }
  end

  def call_tool(tool, **args)
    JSON.parse(tool.call(server_context: @context, **args).to_h[:content].first[:text])
  end

  def proposal(status: "pending", reviewed_at: nil, company: nil)
    changes = { "name" => "Veronto", "main_url" => "https://veronto.example", "description" => GOOD }
    CompanyProposal.create!(
      status: status, proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {},
      proposed_changes: changes, final_changes: changes, duplicate_signals: {},
      reviewed_at: reviewed_at, company: company
    )
  end

  # ---- 1. a description is repairable without engineering -----------------

  test "a company description can be restored, with a reason and its previous value kept" do
    result = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
                       fields: { "description" => GOOD },
                       reason: "Restoring the submitter's original text after an enrichment overwrote it.")

    assert_equal GOOD, @company.reload.description
    edit = @company.quality_review["field_edits"].last
    assert_equal "Restoring the submitter's original text after an enrichment overwrote it.", edit["reason"]
    assert_equal "An enrichment overwrote the original text.", edit["changes"]["description"]["from"]
    refute_equal "blocked", result["result"]
  end

  test "restoring a description requires a reason and refuses text that fails the gate" do
    no_reason = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug, fields: { "description" => GOOD })
    assert_equal "blocked", no_reason["result"]
    assert_match(/requires a `reason`/, no_reason["error"])

    promotional = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
                            fields: { "description" => "Veronto is the leading best-in-class legal platform." }, reason: "test")
    assert_equal "blocked", promotional["result"]
    assert_match(/publication gate/, promotional["error"])
    refute_equal GOOD, @company.reload.description
  end

  test "a broken website can be corrected in place" do
    call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
              fields: { "main_url" => "https://veronto.de" }, reason: "Site moved; the old domain 404s.")

    assert_equal "https://veronto.de", @company.reload.main_url
    assert_equal "veronto.de", @company.canonical_domain, "the dedup key follows the url"
  end

  # ---- 2. a repair is not undone by the next enrichment -------------------

  test "writing a description locks the record against automated description changes" do
    call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug, fields: { "description" => GOOD }, reason: "Restore.")
    assert @company.reload.quality_review["description_locked"]

    locked = proposal(company: @company)
    error = assert_raises(CompanyProposalEnrichmentService::Locked) do
      CompanyProposalEnrichmentService.call(proposal: locked, admin_user: @admin)
    end
    assert_match(/description is locked/, error.message)
  end

  # ---- 3. enrichment cannot rewrite what a reviewer already read ----------

  test "enrichment refuses a record a human has reviewed or approved" do
    reviewed = proposal(reviewed_at: 1.minute.ago)
    assert_raises(CompanyProposalEnrichmentService::Locked) do
      CompanyProposalEnrichmentService.call(proposal: reviewed, admin_user: @admin)
    end

    approved = proposal(status: "approved_to_draft")
    error = assert_raises(CompanyProposalEnrichmentService::Locked) do
      CompanyProposalEnrichmentService.call(proposal: approved, admin_user: @admin)
    end
    assert_match(/already been approved/, error.message)
  end

  test "an explicit request still enriches, and the job records a skip rather than failing" do
    reviewed = proposal(reviewed_at: 1.minute.ago)
    assert_nothing_raised { CompanyProposalEnrichmentService.call(proposal: reviewed, admin_user: @admin, force: true) }

    skipped = proposal(reviewed_at: 1.minute.ago)
    EnrichProposalJob.perform_now(skipped.id, @admin.id)
    assert skipped.reload.agent_details["enrichment_skipped"].present?, "a skip is recorded, not raised"
  end

  # ---- 4. an approval record is not overwritten by a later action ---------

  test "returning a record to its contributor preserves who reviewed it" do
    approved_at = 2.hours.ago.change(usec: 0)
    @company.update_columns(human_reviewed_at: approved_at, quality_status: "needs_review")

    CompanyReviewMarkService.call(company: @company, decision: "return_to_contributor",
                                  admin_user: @admin, instructions: "Please supply a working URL.")

    assert_equal approved_at.to_i, @company.reload.human_reviewed_at.to_i, "the approval timestamp survives"
    assert_equal "awaiting_contributor", @company.review_state
  end

  # ---- 5. duplicate checks see hidden drafts -----------------------------

  test "duplicate_check finds an unpublished draft so a second approval cannot duplicate it" do
    @company.update_columns(visible: false)

    result = call_tool(Mcp::Tools::DuplicateCheckTool, name: "Veronto", url: "https://veronto.example")

    assert_equal "existing_or_possible_duplicate", result["status"]
    match = (result["name_matches"] + result["domain_matches"]).first
    assert_equal @company.id, match["id"]
    assert_equal false, match["visible"], "and the caller can tell it is only a draft"
  end
end
