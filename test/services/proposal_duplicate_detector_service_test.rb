require "test_helper"

class ProposalDuplicateDetectorServiceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @company.update!(name: "ContractPod Technologies", main_url: "https://contractpodai.com")
    @company.update_columns(canonical_domain: "contractpodai.com", quality_status: nil)
  end

  def proposal_for(changes, status: "pending", source_payload: {})
    CompanyProposal.create!(
      status: status,
      proposal_type: "discovery_candidate",
      source: "llm_discovery",
      source_identifier: SecureRandom.uuid,
      source_payload: source_payload,
      proposed_changes: changes,
      final_changes: changes,
      duplicate_signals: {}
    )
  end

  # ---- core-name normalization -------------------------------------------

  test "core name ignores corporate form and glued product suffixes" do
    assert_equal "contractpod", ProposalDuplicateDetectorService.core_name("ContractPodAi")
    assert_equal "contractpod", ProposalDuplicateDetectorService.core_name("ContractPod Technologies")
    assert_equal "midpage", ProposalDuplicateDetectorService.core_name("Midpage AI")
    assert_equal "midpage", ProposalDuplicateDetectorService.core_name("Midpage")
    assert_equal "nextphone", ProposalDuplicateDetectorService.core_name("NextPhone Inc.")
  end

  test "core name refuses to assert identity on a generic or tiny core" do
    assert_nil ProposalDuplicateDetectorService.core_name("Legal AI")
    assert_nil ProposalDuplicateDetectorService.core_name("Contracts Ltd")
    assert_nil ProposalDuplicateDetectorService.core_name("Legal.io")
    assert_nil ProposalDuplicateDetectorService.core_name("Law Group")
    assert_nil ProposalDuplicateDetectorService.core_name("AB")
  end

  test "core name keeps place names whose ending resembles a product suffix" do
    assert_equal "mumbai legal", ProposalDuplicateDetectorService.core_name("Mumbai Legal")
    assert_equal "dubai counsel", ProposalDuplicateDetectorService.core_name("Dubai Counsel")
  end

  # ---- company matching --------------------------------------------------

  test "flags an exact domain match against the live index" do
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({"name" => "Totally Different", "main_url" => "https://contractpodai.com"}))

    assert signals["blocking"]
    assert_equal ["exact_domain"], signals["domain_matches"].map { |m| m["match_type"] }
    assert_equal @company.id, signals["domain_matches"].first["id"]
  end

  test "flags a rebrand whose name and declared domain both differ, via the fetched domain" do
    proposal = proposal_for({"name" => "ContractPodAi", "main_url" => "https://leahai.com/"})

    # Neither key matches on its own: "contractpodai" is not "contractpod technologies",
    # and leahai.com is not contractpodai.com.
    plain = ProposalDuplicateDetectorService.call(proposal: proposal)
    assert_equal ["core_name"], plain["name_matches"].map { |m| m["match_type"] },
                 "core-name should still catch the rebrand by name"

    # And when the site fetch resolves the redirect, the domain key catches it too.
    resolved = ProposalDuplicateDetectorService.call(proposal: proposal, extra_domains: ["contractpodai.com"])
    assert_equal ["exact_domain"], resolved["domain_matches"].map { |m| m["match_type"] }
    assert_match(/rebrand/, resolved["recommended_action"])
  end

  test "matches a hidden draft, which would otherwise mint a second row" do
    @company.update_columns(visible: false)
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({"name" => "ContractPod Technologies"}))

    assert signals["blocking"]
    refute signals["name_matches"].first["visible"]
  end

  test "ignores a rejected company" do
    @company.update_columns(quality_status: "rejected")
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({"name" => "ContractPod Technologies"}))

    refute signals["blocking"]
  end

  test "reports no match for an unrelated candidate" do
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({"name" => "Zephyr Escrow Analytics", "main_url" => "https://zephyrescrow.example"}))

    refute signals["blocking"]
    assert_empty signals["name_matches"]
    assert_empty signals["domain_matches"]
    assert_nil signals["recommended_action"]
  end

  # ---- sibling-proposal matching -----------------------------------------

  test "two open proposals for the same company see each other" do
    first = proposal_for({ "name" => "Pactolane", "main_url" => "https://www.pactolane.com" }, status: "ready_for_review")
    second = proposal_for({"name" => "Pactolane", "main_url" => "https://www.pactolane.com"})

    signals = ProposalDuplicateDetectorService.call(proposal: second)
    match = signals["proposal_matches"].find { |m| m["proposal_id"] == first.id }

    assert signals["blocking"]
    assert match, "expected the sibling proposal to be reported"
    assert match["is_older"], "the earlier record should be marked as such"
    assert_match(/Proposal ##{first.id} covers the same company/, signals["recommended_action"])
  end

  test "a resolved sibling drops out of the comparison set" do
    first = proposal_for({ "name" => "Gaskiya" }, status: "ready_for_review")
    second = proposal_for({"name" => "Gaskiya"})

    assert ProposalDuplicateDetectorService.call(proposal: second)["blocking"]

    first.update!(status: "rejected")
    refute ProposalDuplicateDetectorService.call(proposal: second)["blocking"]
  end

  test "a proposal is not a duplicate of the company it created itself" do
    proposal = proposal_for({ "name" => "ContractPod Technologies", "main_url" => "https://contractpodai.com" })
    assert ProposalDuplicateDetectorService.call(proposal: proposal)["blocking"]

    proposal.update!(company: @company)
    refute ProposalDuplicateDetectorService.call(proposal: proposal)["blocking"],
           "promoting an approved draft must not be blocked by the row the proposal itself minted"
  end

  test "a proposal rejected as a duplicate still reports the entry that was kept" do
    proposal = proposal_for({ "name" => "ContractPod Technologies", "main_url" => "https://contractpodai.com" })
    proposal.update!(status: "rejected", company: @company)

    assert ProposalDuplicateDetectorService.call(proposal: proposal)["blocking"],
           "the company link on a rejected duplicate records what was kept, not what it created"
  end

  test "a proposal never matches itself" do
    proposal = proposal_for({"name" => "Solo Candidate", "main_url" => "https://solo.example"})

    assert_empty ProposalDuplicateDetectorService.call(proposal: proposal)["proposal_matches"]
  end
end
