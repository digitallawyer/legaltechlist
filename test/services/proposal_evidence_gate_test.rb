require "test_helper"

# Covers the two rules that stop an unchecked record from reaching publication:
# a proposal nothing was retrieved for is "unverified", and an unverified or
# never-enriched proposal cannot publish however complete its fields are.
class ProposalEvidenceGateTest < ActiveSupport::TestCase
  COMPLETE_CHANGES = {
    "name" => "Zephyr Escrow Analytics",
    "main_url" => "https://zephyrescrow.example",
    "location" => "Lyon, France",
    "founded_date" => "2019",
    "description" => "Zephyr Escrow Analytics builds escrow reconciliation software for law firms, covering client-account ledgers, three-way reconciliation and regulatory reporting for trust accounts.",
    "category_id" => nil,
    "business_model_ids" => [],
    "target_client_ids" => []
  }.freeze

  setup do
    @category = categories(:one)
    @business_model = business_models(:one)
    @target_client = target_clients(:one)
  end

  def proposal_with(agent_details: {}, enriched: true, changes: {})
    final = COMPLETE_CHANGES.merge(
      "category_id" => @category.id,
      "business_model_id" => @business_model.id,
      "business_model_ids" => [@business_model.id],
      "target_client_id" => @target_client.id,
      "target_client_ids" => [@target_client.id]
    ).merge(changes)

    CompanyProposal.create!(
      status: "ready_for_review",
      proposal_type: "discovery_candidate",
      source: "llm_discovery",
      source_identifier: SecureRandom.uuid,
      source_payload: {},
      proposed_changes: final,
      final_changes: final,
      duplicate_signals: {},
      enriched_at: enriched ? Time.current : nil,
      agent_details: agent_details
    )
  end

  def fetched_page(url = "https://zephyrescrow.example")
    { "site_evidence" => { "pages" => [{ "label" => "website", "url" => url, "final_url" => url, "status" => "fetched", "text" => "Escrow reconciliation software for law firms." }] } }
  end

  test "a complete but unresearched proposal is not publishable" do
    report = CompanyProposalQualityService.call(proposal_with(enriched: false))

    refute report["publish_ready"]
    assert_equal "unverified", report["verification_state"]
    assert_includes report["blockers"], "This record has not been researched yet. Run Enrich before publishing."
  end

  test "self-reported links alone leave a record unverified and unpublishable" do
    proposal = proposal_with(changes: { "crunchbase_url" => "https://crunchbase.com/organization/zephyr", "linkedin_url" => "https://linkedin.com/company/zephyr" })
    report = CompanyProposalQualityService.call(proposal)

    assert report["usable_source_evidence_count"].positive?, "the links are still counted as source evidence"
    assert_equal 0, report["independent_evidence_count"]
    assert_equal "unverified", report["verification_state"]
    refute report["publish_ready"]
    assert(report["blockers"].any? { |b| b.include?("No independently retrieved evidence") })
  end

  test "one retrieved page makes the record evidence-backed and publishable" do
    report = CompanyProposalQualityService.call(proposal_with(agent_details: fetched_page))

    assert_equal 1, report["fetched_page_count"]
    assert_equal "evidence_backed", report["verification_state"]
    assert report["publish_ready"], report["blockers"].inspect
  end

  test "a search citation also counts as independent evidence" do
    details = { "web_research" => { "results" => [{ "title" => "Zephyr Escrow", "url" => "https://news.example/zephyr" }] } }
    report = CompanyProposalQualityService.call(proposal_with(agent_details: details))

    assert_equal "evidence_backed", report["verification_state"]
    assert report["publish_ready"], report["blockers"].inspect
  end

  test "a blocked site says so, rather than reporting that nothing was tried" do
    details = { "site_evidence" => { "pages" => [{ "label" => "linkedin", "url" => "https://linkedin.com/company/zephyr", "status" => "blocked", "reason" => "linkedin_requires_sign_in" }] } }
    report = CompanyProposalQualityService.call(proposal_with(agent_details: details))

    refute report["publish_ready"]
    assert(report["blockers"].any? { |b| b.include?("could not be retrieved") && b.include?("linkedin_requires_sign_in") })
  end

  # Lists read a cached report so they do not recompute per row. A report written before
  # the verification gate existed would claim a record is ready while the detail view
  # blocks it, so it must not be trusted.
  test "a cached report predating the verification gate is ignored rather than trusted" do
    proposal = proposal_with(enriched: false)
    proposal.update!(agent_details: proposal.agent_details.merge("quality" => { "publish_ready" => true, "score" => 100, "blockers" => [] }))

    assert_nil proposal.cached_quality_report
    refute CompanyProposalQualityService.call(proposal)["publish_ready"]
  end

  test "a current cached report is still reused" do
    proposal = proposal_with(agent_details: fetched_page)
    fresh = CompanyProposalQualityService.call(proposal)
    proposal.update!(agent_details: proposal.agent_details.merge("quality" => fresh))

    assert_equal fresh, proposal.reload.cached_quality_report
  end

  test "completeness and verification are reported as separate facts" do
    report = CompanyProposalQualityService.call(proposal_with(enriched: false))

    assert_equal 100, report["score"], "every field is filled in"
    assert_equal "unverified", report["verification_state"], "and none of it was checked"
  end
end
