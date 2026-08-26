require "test_helper"

# Two workflow rules a reviewer depends on:
#   a resolved record leaves the active queue but stays retrievable, and
#   a record waiting on its contributor is nobody's review task in the meantime.
class ReviewQueueHygieneTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in admin_users(:one)
    @company = companies(:one)
    @company.update!(name: "Pactolane", main_url: "https://www.pactolane.com")
    @company.update_columns(canonical_domain: "pactolane.com", quality_status: nil, fingerprint: @company.calculated_fingerprint)
  end

  def duplicate_proposal(name: "Pactolane", url: "https://www.pactolane.com")
    changes = {
      "name" => name, "main_url" => url, "location" => "Lyon, France",
      "description" => "Pactolane builds contract lifecycle management software for legal and procurement teams.",
      "category_id" => categories(:one).id,
      "business_model_id" => business_models(:one).id, "business_model_ids" => [business_models(:one).id],
      "target_client_id" => target_clients(:one).id, "target_client_ids" => [target_clients(:one).id]
    }
    CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {}, submitter_email: "founder@pactolane.example",
      proposed_changes: changes, final_changes: changes, duplicate_signals: {},
      enriched_at: Time.current, agent_details: researched_agent_details(url: url)
    )
  end

  # ---- item 1: rejected duplicates leave the active queue -----------------

  test "the duplicate view lists only open work, never resolved or published records" do
    open_dup = duplicate_proposal
    resolved = duplicate_proposal(url: "https://pactolane.io")
    resolved.update!(status: "rejected", agent_details: resolved.agent_details.merge("canonical_record" => { "company_id" => @company.id }))
    published = duplicate_proposal(url: "https://pactolane.co")
    published.update!(status: "published")

    get custom_admin_company_proposals_path(status: "duplicate")

    assert_response :success
    assert_select "td", text: /Pactolane/
    body = response.body
    assert_includes body, "/admin/proposals/#{open_dup.id}"
    refute_includes body, "/admin/proposals/#{resolved.id}", "a resolved duplicate is not active work"
    refute_includes body, "/admin/proposals/#{published.id}", "a published record is not active work"
  end

  test "resolved duplicates stay retrievable under their own filter with the record that was kept" do
    resolved = duplicate_proposal
    resolved.update!(
      status: "rejected",
      rejection_reason: "Duplicate of Pactolane (##{@company.id}); that record is canonical.",
      agent_details: resolved.agent_details.merge("canonical_record" => { "company_id" => @company.id, "resolved_by" => "reviewer@example.com" })
    )

    get custom_admin_company_proposals_path(status: "resolved_duplicates")

    assert_response :success
    assert_includes response.body, "/admin/proposals/#{resolved.id}"
    assert_equal @company.id, resolved.reload.agent_details.dig("canonical_record", "company_id"), "the canonical link survives"
    assert resolved.rejection_reason.present?, "the audit trail survives"
  end

  test "rejecting a duplicate returns the reviewer to the queue it disappeared from" do
    proposal = duplicate_proposal

    post reject_custom_admin_company_proposal_path(proposal),
         params: { duplicate_of_company_id: @company.id, return_status: "duplicate" }

    assert_redirected_to custom_admin_company_proposals_path(status: "duplicate")
    follow_redirect!
    refute_includes response.body, "/admin/proposals/#{proposal.id}", "it is gone from the queue without a manual reload"
    assert_equal "rejected", proposal.reload.status
  end

  # ---- item 2: the overview agrees with the detail page -------------------

  test "a proposal blocked on its detail page appears in the duplicate view even with a stale stored column" do
    proposal = duplicate_proposal
    # Exactly the state that hid 11 proposals: the record is a duplicate, but the column
    # the overview used to filter on was written before that was true.
    proposal.update_columns(duplicate_signals: {})

    get custom_admin_company_proposals_path(status: "duplicate")

    assert_response :success
    assert_includes response.body, "/admin/proposals/#{proposal.id}"
    assert proposal.reload.duplicate_signals["blocking"], "and the stored column is brought back into line"
  end

  # ---- item 3: compare before resolving -----------------------------------

  test "the duplicate blocker offers a comparison before any resolution" do
    proposal = duplicate_proposal

    get custom_admin_company_proposal_path(proposal)
    assert_response :success
    assert_select "a[href=?]", compare_duplicate_custom_admin_company_proposal_path(proposal, company_id: @company.id)

    get compare_duplicate_custom_admin_company_proposal_path(proposal, company_id: @company.id)
    assert_response :success
    assert_select "h1", text: /Compare/
    assert_select "th", text: /Field/
  end

  # ---- item 4: return to contributor --------------------------------------

  test "returning a company to its contributor takes it out of the review queue and records why" do
    CompanyProposal.create!(
      status: "published", proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {}, submitter_email: "founder@pactolane.example",
      proposed_changes: {}, final_changes: {}, duplicate_signals: {}, company: @company
    )

    post custom_admin_company_mark_review_path(@company.id), params: {
      decision: "return_to_contributor",
      contributor_instructions: "The website returns a 404 — please supply a current URL.",
      contributor_fields: %w[main_url]
    }

    assert_redirected_to custom_admin_companies_path(review_state: "awaiting_contributor")
    @company.reload
    assert_equal "awaiting_contributor", @company.review_state
    refute @company.visible?, "an incomplete record should not stay public while it waits"

    request = @company.quality_review["current_contributor_request"]
    assert_equal "The website returns a 404 — please supply a current URL.", request["instructions"]
    assert_equal ["main_url"], request["fields"]
    assert_equal "founder@pactolane.example", request["contributor_email"], "the contributor is resolved from the originating proposal"

    # And it is out of the reviewer's active queues, without being deleted.
    refute_includes Company.review_state_not_reviewed.ids, @company.id
    refute_includes Company.review_state_in_review.ids, @company.id
    assert_includes Company.review_state_awaiting_contributor.ids, @company.id
  end

  test "returning requires instructions and refuses on a rejected record" do
    post custom_admin_company_mark_review_path(@company.id), params: { decision: "return_to_contributor", contributor_instructions: "  " }
    assert_redirected_to custom_admin_company_review_path(@company.id)
    assert_match(/what the contributor needs/i, flash[:alert])
    refute_equal "awaiting_contributor", @company.reload.review_state

    @company.update_columns(quality_status: "rejected")
    post custom_admin_company_mark_review_path(@company.id), params: { decision: "return_to_contributor", contributor_instructions: "Fix the URL." }
    assert_match(/rejected record cannot be returned/i, flash[:alert])
  end

  test "successive returns append to the history rather than replacing it" do
    2.times do |i|
      post custom_admin_company_mark_review_path(@company.id), params: {
        decision: "return_to_contributor", contributor_instructions: "Round #{i + 1} instructions."
      }
      @company.reload.update_columns(quality_status: nil) if i.zero?
    end

    assert_equal 2, @company.reload.quality_review["contributor_requests"].size
    assert_equal "Round 2 instructions.", @company.quality_review["current_contributor_request"]["instructions"]
  end
end
