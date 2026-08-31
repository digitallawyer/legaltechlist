require "test_helper"

# The Company tab as a working surface: reviews run without throwing the reviewer out
# of the draft, findings appear beside the record, the default list is the publishing
# workload rather than the whole index, and a batch review is capped and queued.
class CompanyReviewWorkflowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in admin_users(:one)
    @company = companies(:one)
    @company.update!(name: "Pactolane", main_url: "https://www.pactolane.com")
    @company.update_columns(quality_status: nil, fingerprint: @company.calculated_fingerprint)
  end

  def agent_review_run(company: @company, status: "succeeded", run_type: "company_agent_review")
    PipelineRun.create!(
      name: "Agent company review: #{company.name}", run_type: run_type, status: status,
      agent_name: "CompanyEvidenceAgent+CompanyVerifierAgent", records_processed: 1,
      details: {
        "company_id" => company.id,
        "evidence" => [{ "title" => "Company website", "url" => "https://www.pactolane.com", "summary" => "Stored main url." }],
        "description_draft" => { "proposed_description" => "Pactolane builds contract lifecycle management software for legal and procurement teams." },
        "description_critic" => { "verdict" => "pass", "issues" => [], "suggested_revision" => "" },
        "review_coordinator" => { "status" => "needs_more_evidence", "reasons" => ["The critic wanted more evidence."], "recommended_actions" => ["Check the website."] },
        "proposed_corrections" => { "quality_score" => 90, "proposed_description" => "Pactolane builds contract lifecycle management software for legal and procurement teams." },
        "risks" => []
      }
    )
  end

  def duplicate_review_run(company: @company)
    PipelineRun.create!(
      name: "Duplicate-domain review: #{company.name}", run_type: "duplicate_domain_review", status: "succeeded",
      agent_name: "DuplicateReviewAgent", records_processed: 1,
      details: {
        "company_id" => company.id,
        "duplicate_review" => {
          "overall_recommendation" => "related_entities", "rationale" => "The records share a domain.",
          "pair_reviews" => [{ "candidate_company_id" => companies(:two).id, "relationship" => "related", "confidence" => "low", "reasons" => ["Domains match."] }],
          "unresolved_questions" => ["Product or company record?"]
        }
      }
    )
  end

  # ---- items 1, 2, 4: findings live on the draft ---------------------------

  test "the draft shows the latest agent review and duplicate review findings inline" do
    agent_review_run
    duplicate_review_run

    get custom_admin_company_review_path(@company.id)

    assert_response :success
    assert_select "#agent-review h2", text: /Agent review/
    assert_select "#duplicate-review h2", text: /Duplicate review/
    assert_select "li", text: "The critic wanted more evidence."
    assert_select "li", text: "Check the website."
    assert_select "td", text: /Domains match\./
    # The findings are actionable from here, not just readable.
    assert_select "form[action=?]", apply_custom_admin_agent_review_path(PipelineRun.where(run_type: "company_agent_review").last)
  end

  test "the draft says so plainly when no review has been run" do
    get custom_admin_company_review_path(@company.id)

    assert_response :success
    assert_select "#agent-review", text: /No agent review has been run/
    assert_select "#duplicate-review", text: /No duplicate review has been run/
  end

  test "running either review returns to the draft rather than a separate page" do
    CompanyAgentReviewService.stub(:call, agent_review_run) do
      post custom_admin_company_agent_review_path(@company.id)
    end
    assert_redirected_to custom_admin_company_review_path(@company.id, anchor: "agent-review")

    DuplicateDomainReviewService.stub(:call, duplicate_review_run) do
      post custom_admin_company_duplicate_review_path(@company.id)
    end
    assert_redirected_to custom_admin_company_review_path(@company.id, anchor: "duplicate-review")
  end

  test "applying a correction from the draft comes back to the draft" do
    run = agent_review_run

    post apply_custom_admin_agent_review_path(run), params: { fields: ["quality_score"], return_to: "company" }

    assert_redirected_to custom_admin_company_review_path(@company.id, anchor: "agent-review")
    assert_equal 90, @company.reload.quality_score
  end

  test "the standalone review page offers a way back to the company it came from" do
    run = agent_review_run

    get custom_admin_agent_review_path(run)

    assert_response :success
    assert_select "a[href=?]", custom_admin_company_review_path(@company.id), text: /Back to company draft/
  end

  # ---- item 3: the Company tab is a working queue -------------------------

  test "the default company list holds only records still needing a decision" do
    needs_review = @company
    verified = companies(:two)
    verified.update_columns(quality_status: "verified")
    rejected = Company.create!(
      name: "Rejected Co", location: "Boston, MA", description: "A rejected legal technology record.",
      category: categories(:one), target_client: target_clients(:one), business_models: [business_models(:one)]
    )
    rejected.update_columns(quality_status: "rejected")

    get custom_admin_companies_path

    assert_response :success
    assert_includes response.body, "/admin/review/companies/#{needs_review.id}"
    refute_includes response.body, "/admin/review/companies/#{verified.id}", "an approved record is not workload"
    refute_includes response.body, "/admin/review/companies/#{rejected.id}", "a rejected record is not workload"
  end

  test "verified and rejected records stay reachable through their own filters" do
    verified = companies(:two)
    verified.update_columns(quality_status: "verified")

    get custom_admin_companies_path(review_state: "verified")
    assert_includes response.body, "/admin/review/companies/#{verified.id}"

    get custom_admin_companies_path(review_state: "all")
    assert_includes response.body, "/admin/review/companies/#{verified.id}"
    assert_includes response.body, "/admin/review/companies/#{@company.id}"
  end

  test "deciding a record sends the reviewer back to the queue it has left" do
    post custom_admin_company_mark_review_path(@company.id), params: { decision: "verified" }

    assert_redirected_to custom_admin_companies_path
    follow_redirect!
    refute_includes response.body, "/admin/review/companies/#{@company.id}"
  end

  # ---- item 5: controlled batch review ------------------------------------

  test "a batch review queues one job per selected company without publishing anything" do
    other = companies(:two)

    assert_enqueued_jobs 2, only: CompanyAgentReviewJob do
      post batch_agent_review_custom_admin_companies_path, params: { company_ids: [@company.id, other.id] }
    end

    assert_redirected_to custom_admin_companies_path
    assert_match(/Queued agent reviews for 2 companies/, flash[:notice])
    refute @company.reload.visible? && @company.quality_status == "verified", "a batch review never decides anything"
  end

  test "a batch larger than the cap is refused rather than partially run" do
    ids = (1..11).map { |i| i }

    assert_no_enqueued_jobs only: CompanyAgentReviewJob do
      post batch_agent_review_custom_admin_companies_path, params: { company_ids: ids }
    end
    assert_match(/at most 10/, flash[:alert])
  end

  test "an empty selection is refused" do
    assert_no_enqueued_jobs only: CompanyAgentReviewJob do
      post batch_agent_review_custom_admin_companies_path, params: { company_ids: [] }
    end
    assert_match(/Select at least one company/, flash[:alert])
  end

  test "a company already mid-review is skipped rather than queued twice" do
    agent_review_run(status: "running")

    assert_enqueued_jobs 0, only: CompanyAgentReviewJob do
      post batch_agent_review_custom_admin_companies_path, params: { company_ids: [@company.id] }
    end
    assert_match(/already had a review in progress/, flash[:notice])
  end

  test "the company list offers the batch control" do
    get custom_admin_companies_path

    assert_response :success
    assert_select "form[action=?]", batch_agent_review_custom_admin_companies_path
    assert_select "input[name=?]", "company_ids[]"
    assert_select "input[data-batch-select-all]"
  end
end
