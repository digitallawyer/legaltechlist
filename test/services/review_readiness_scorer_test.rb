require "test_helper"

class ReviewReadinessScorerTest < ActiveSupport::TestCase
  GOOD_DESCRIPTION = "Zephyr builds escrow reconciliation software for law firms, covering client-account ledgers, three-way reconciliation and regulatory reporting for trust accounts.".freeze

  def company(name: "Zephyr", url: "https://zephyr.example", description: GOOD_DESCRIPTION, created_at: 5.days.ago, **attrs)
    record = Company.create!(
      name: name, location: "Boston, MA", description: description.presence || "placeholder",
      category: categories(:one), target_client: target_clients(:one), business_models: [business_models(:one)],
      main_url: url
    )
    record.update_columns({ created_at: created_at, description: description }.merge(attrs))
    record.reload
  end

  test "a complete record with a live site is high priority" do
    score = ReviewReadinessScorer.call(company)

    assert_equal "high", score[:level]
    assert_equal "High priority", score[:label]
    assert_match(/Official website on file, description present/, score[:reasons].first)
    assert_match(/pending 5 days/, score[:reasons].first)
  end

  test "a thin description drops to low" do
    assert_equal "low", ReviewReadinessScorer.call(company(description: "Legal software."))[:level]
  end

  test "no website is low however good the description" do
    assert_equal "low", ReviewReadinessScorer.call(company(url: nil))[:level]
  end

  test "a broken website is low and says so" do
    score = ReviewReadinessScorer.call(company(url_status: Company::URL_STATUS_BROKEN))

    assert_equal "low", score[:level]
    assert_match(/not responding/, score[:reasons].first)
  end

  test "a duplicate flag with a thin description is low and named" do
    record = company(description: "Legal software.")
    score = ReviewReadinessScorer.call(record, duplicate_ids: [record.id])

    assert_equal "low", score[:level]
    assert_match(/possible duplicate/, score[:reasons].first)
  end

  test "a record with nothing to go on is unassessed rather than given a level" do
    score = ReviewReadinessScorer.call(company(url: nil, description: ""))

    assert_equal "needs_assessment", score[:level]
    assert_match(/nothing here to review/, score[:reasons].first)
  end

  # The safeguard that matters: a hard record must not sit at the bottom forever.
  test "age promotes a stagnating record a whole level" do
    fresh = ReviewReadinessScorer.call(company(description: "Legal software.", created_at: 5.days.ago))
    stale = ReviewReadinessScorer.call(company(name: "Zephyr Two", description: "Legal software.", created_at: 200.days.ago))

    assert_equal "low", fresh[:level]
    assert_equal "medium", stale[:level], "an old low-readiness record climbs"
    assert stale[:promoted_for_age]
    assert_match(/moved up because it has been waiting/, stale[:reasons].first)
  end

  test "ordering puts ready records first and older records ahead within a level" do
    ready_new = company(name: "Ready New", created_at: 2.days.ago)
    ready_old = company(name: "Ready Old", created_at: 60.days.ago)
    thin = company(name: "Thin", description: "Legal software.", created_at: 1.day.ago)

    ordered = ReviewReadinessScorer.order([thin, ready_new, ready_old]).map { |c, _| c.name }

    assert_equal ["Ready Old", "Ready New", "Thin"], ordered
    assert_equal "Ready Old", ordered.first, "older of two equally ready records comes first"
    assert_equal "Thin", ordered.last
  end

  test "scoring never writes to the company" do
    record = company
    assert_no_changes -> { record.reload.attributes } do
      ReviewReadinessScorer.call(record)
    end
  end
end
