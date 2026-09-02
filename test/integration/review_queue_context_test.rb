require "test_helper"

# Finishing a record returns the reviewer to the list they were working through, with
# their filters, sort and page intact — rather than to the default view they then have
# to rebuild for every record.
class ReviewQueueContextTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in admin_users(:one)
    @company = companies(:one)
    @company.update_columns(quality_status: nil)
  end

  QUEUE = { "review_state" => "not_reviewed", "category_id" => "1", "sort" => "readiness", "page" => "2" }.freeze

  test "company row links carry the current list state" do
    get custom_admin_companies_path(review_state: "not_reviewed", sort: "readiness")

    assert_response :success
    assert_select "a[href*=?]", "queue%5Breview_state%5D=not_reviewed"
    assert_select "a[href*=?]", "queue%5Bsort%5D=readiness"
  end

  test "completing a company returns to the same filtered queue" do
    post custom_admin_company_mark_review_path(@company.id), params: { decision: "verified", queue: QUEUE }

    assert_response :redirect
    target = @response.headers["Location"]
    assert_includes target, "/admin/app/companies?"
    QUEUE.each { |key, value| assert_includes target, "#{key}=#{value}" }
  end

  test "a record opened directly still falls back to the default list" do
    post custom_admin_company_mark_review_path(@company.id), params: { decision: "verified" }

    assert_redirected_to custom_admin_companies_path
  end

  test "the company draft offers a way back to the queue it came from" do
    get custom_admin_company_review_path(@company.id, queue: QUEUE)

    assert_response :success
    assert_select "a", text: /Back to the company queue/
  end

  test "rejecting a proposal returns to the same review queue" do
    changes = { "name" => "Zephyr", "main_url" => "https://zephyr.example" }
    proposal = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {},
      proposed_changes: changes, final_changes: changes, duplicate_signals: {}
    )
    queue = { "status" => "duplicate", "q" => "zephyr" }

    post reject_custom_admin_company_proposal_path(proposal), params: { queue: queue }

    target = @response.headers["Location"]
    assert_includes target, "/admin/proposals?"
    assert_includes target, "status=duplicate"
    assert_includes target, "q=zephyr"
  end

  # The state is rebuilt from allowlisted params, so it cannot be used to send a
  # reviewer off-site or to an arbitrary path.
  test "unknown and hostile queue keys are discarded" do
    post custom_admin_company_mark_review_path(@company.id),
         params: { decision: "verified", queue: { "review_state" => "verified", "evil" => "//example.com", "host" => "example.com" } }

    target = URI.parse(@response.headers["Location"])
    assert_equal "/admin/app/companies", target.path, "the path is rebuilt, never taken from the parameter"
    assert_equal "review_state=verified", target.query, "only allowlisted keys survive"
  end
end
