require "test_helper"
require "minitest/mock"

class RecordJudgeServiceTest < ActiveSupport::TestCase
  PAGE = { "label" => "website", "url" => "https://acme.example", "final_url" => "https://acme.example/", "status" => "fetched", "http_status" => 200, "renders_text" => true,
           "title" => "Acme - contract review", "meta_description" => "AI contract review.", "text" => "Acme builds contract review software for in-house legal teams. It extracts clauses and compares them with playbooks." }.freeze
  GOOD = { "scope" => "in_scope", "decision" => "list", "confidence" => 0.9, "reason" => "Contract review software.", "successor_note" => "", "model" => "gpt-test",
           "description" => "Acme builds contract review software for in-house legal teams. It extracts clauses and compares them with playbooks.",
           "support_quotes" => ["builds contract review software for in-house legal teams", "compares them with playbooks"] }.freeze

  setup do
    @company = companies(:two)
    @company.update_columns(main_url: "https://acme.example/", name: "Acme")
    @company.evidence_snapshots.delete_all
    @company.review_events.delete_all
  end

  def judge(pages: [PAGE], answer: GOOD, **options)
    fetcher = Struct.new(:call).new({ "pages" => pages })
    calls = []
    SiteEvidenceFetcherService.stub(:new, ->(**) { fetcher }) do
      RecordJudgeAgent.stub(:call, ->(**args) { calls << args; answer && answer.dup }) do
        result = RecordJudgeService.call(company: @company, **options)
        [result, calls]
      end
    end
  end

  test "a readable site is judged, the answer is grounded in quotes from the page, and the judgement is recorded" do
    result, calls = judge

    assert_equal "list", result["decision"]
    assert_equal "2/2", result["quotes_verified"]
    assert_equal 1, calls.size
    assert_equal 1, @company.evidence_snapshots.count
    event = @company.review_events.judgements.last
    assert_equal result["evidence_hash"], event.evidence_hash
    assert_equal "list", event.decision
  end

  test "a listing whose quotes are not on the page is downgraded to needs_work and keeps no description" do
    result, = judge(answer: GOOD.merge("support_quotes" => ["a sentence the page never says"]))

    assert_equal "needs_work", result["decision"]
    assert_equal "list", result["downgraded_from"]
    assert_equal "", result["description"]
  end

  test "a listing that fails the publication gate is downgraded" do
    result, = judge(answer: GOOD.merge("description" => "Acme appears to build contract review software for in-house legal teams across the world today."))

    assert_equal "needs_work", result["decision"]
    assert_match(/publication gate/, result["reason"])
  end

  test "the company's own name does not trip the voice check" do
    @company.update_columns(name: "We Base Solutions")
    text = "We Base Solutions builds contract review software for in-house legal teams. It extracts clauses and compares them with playbooks."
    result, = judge(answer: GOOD.merge("description" => text))

    assert_equal "list", result["decision"]
  end

  test "an unreadable site calls no model and invents nothing" do
    result, calls = judge(pages: [{ "label" => "website", "url" => "https://acme.example", "status" => "error", "reason" => "dns_failure" }])

    assert_equal "needs_work", result["decision"]
    assert_equal "unreadable", result["scope"]
    assert_empty calls
    assert_match(/dns_failure/, result["reason"])
  end

  test "a record without a website is needs_work without any fetch" do
    @company.update_columns(main_url: nil)
    result, calls = judge

    assert_equal "needs_work", result["decision"]
    assert_empty calls
  end

  test "unchanged evidence returns the earlier judgement instead of a second model call" do
    judge
    result, calls = judge

    assert result["reused"]
    assert_equal "list", result["decision"]
    assert_empty calls
    assert_equal 1, @company.review_events.judgements.count
  end

  test "a JavaScript shell is judged from its title and meta description and says it renders no text" do
    shell = PAGE.merge("renders_text" => false, "text" => "AI contract review.")
    _, calls = judge(pages: [shell])

    assert_equal false, calls.first[:pages].first[:renders_text]
  end

  test "a close needs a quote from the pages that shows why; without one it is needs_work" do
    law = GOOD.merge("scope" => "law_firm", "decision" => "close", "description" => "", "support_quotes" => [])
    result, = judge(answer: law)
    assert_equal "needs_work", result["decision"]
    assert_equal "close", result["downgraded_from"]

    with_quote = law.merge("support_quotes" => ["contract review software for in-house legal teams"])
    result, = judge(answer: with_quote, refresh: true)
    assert_equal "close", result["decision"]
    assert_equal true, result["grounded"]
  end

  test "a refused description is retried once with the reasons, and the better answer is kept" do
    bad = GOOD.merge("description" => "Acme appears to build contract review software for in-house legal teams across the world today.")
    answers = [bad, GOOD]
    feedbacks = []
    fetcher = Struct.new(:call).new({ "pages" => [PAGE] })
    result = SiteEvidenceFetcherService.stub(:new, ->(**) { fetcher }) do
      RecordJudgeAgent.stub(:call, ->(**args) { feedbacks << args[:feedback]; answers.shift.dup }) do
        RecordJudgeService.call(company: @company)
      end
    end

    assert_equal "list", result["decision"]
    assert result["retried"]
    assert_nil feedbacks.first
    assert_match(/was refused/, feedbacks.last)
  end

  test "a page that refused us after redirecting off-site is still judged from where it ended up" do
    blocked = { "label" => "website", "url" => "https://acme.example", "final_url" => "https://forsale.godaddy.com/forsale/acme.example", "status" => "blocked", "reason" => "bot_blocked_403" }
    parked = GOOD.merge("scope" => "parked_or_for_sale", "decision" => "close", "description" => "", "support_quotes" => ["forsale godaddy com forsale acme example"])
    result, calls = judge(pages: [blocked], answer: parked)

    assert_equal "close", result["decision"], "the address itself is the evidence"
    assert_equal 1, calls.size
    assert_equal false, calls.first[:pages].first[:fetched]
    assert_match(/forsale\.godaddy\.com/, calls.first[:pages].first[:final_url])
  end
end
