require "test_helper"
require "minitest/mock"

# The source safeguards and the entity gate are enforced here rather than requested in
# the prompt, so these test the enforcement rather than the model.
class DescriptionVerificationServiceTest < ActiveSupport::TestCase
  PAGES = [
    { "label" => "website", "url" => "https://www.legaion.com", "final_url" => "https://www.legaion.com", "status" => "fetched",
      "title" => "LEGAION", "text" => "LEGAION is an AI legal intelligence platform for law firms." },
    { "label" => "website_terms", "url" => "https://www.legaion.com/terms", "final_url" => "https://www.legaion.com/terms", "status" => "fetched",
      "title" => "Terms", "text" => "These terms are between you and Aidvocates, Inc., operator of LEGAION." }
  ].freeze

  def evidence(pages = PAGES)
    { "mode" => "http_fetch", "pages" => pages }
  end

  def run_with(model_output, pages: PAGES, **overrides)
    args = {
      company_name: "Aidvocates Inc.", company_url: "https://www.legaion.com",
      proposed_description: "LEGAION is a legal software platform built by Aidvocates, Inc. for law firms.",
      site_evidence: evidence(pages)
    }.merge(overrides)

    ENV["DESCRIPTION_VERIFICATION_USE_LLM"] = "true"
    ENV["OPENAI_API_KEY"] ||= "test-key"
    DescriptionVerificationAgent.stub(:call, model_output) { DescriptionVerificationService.call(**args) }
  ensure
    ENV.delete("DESCRIPTION_VERIFICATION_USE_LLM")
  end

  def approving_output(**overrides)
    {
      "decision" => "APPROVE",
      "verified_company" => "Aidvocates, Inc.",
      "verified_product" => "LEGAION",
      "company_product_relationship" => "Aidvocates, Inc. operates the LEGAION platform.",
      "accuracy_assessment" => "Every claim appears on the retrieved pages.",
      "verified_claims" => ["AI legal intelligence for law firms"],
      "issues_found" => ["None"],
      "corrected_description" => nil,
      "sources" => ["https://www.legaion.com/terms"],
      "confidence" => "HIGH"
    }.merge(overrides)
  end

  # ---- entity identity ----------------------------------------------------

  test "keeps the company and the product distinct rather than interchangeable" do
    result = run_with(approving_output)

    assert_equal "APPROVE", result["decision"]
    assert_equal "Aidvocates, Inc.", result["verified_company"]
    assert_equal "LEGAION", result["verified_product"]
    assert result["entity_resolved"]
  end

  test "an unresolved company-product relationship cannot be approved" do
    result = run_with(approving_output("verified_product" => nil, "company_product_relationship" => nil))

    assert_equal "MANUAL_REVIEW", result["decision"], "identity has to be settled before a description can pass"
    refute result["entity_resolved"]
    assert(result["validation_notes"].any? { |n| n.include?("could not both be identified") })
  end

  # ---- source safeguards --------------------------------------------------

  test "citations that were not among the retrieved pages are dropped" do
    result = run_with(approving_output("sources" => ["https://www.legaion.com/terms", "https://some-directory.example/legaion"]))

    assert_equal ["https://www.legaion.com/terms"], result["sources"]
    assert_equal ["https://some-directory.example/legaion"], result["rejected_sources"]
    assert_equal "LOW", result["confidence"], "confidence falls when a citation is thrown away"
  end

  test "an approval with no surviving source is downgraded" do
    result = run_with(approving_output("sources" => ["https://third-party-directory.example/x"]))

    assert_equal "MANUAL_REVIEW", result["decision"]
    assert_empty result["sources"]
    assert(result["validation_notes"].any? { |n| n.include?("No verifiable source page") })
  end

  test "trailing slashes and www do not make a retrieved page look uncited" do
    result = run_with(approving_output("sources" => ["https://legaion.com/terms/"]))

    assert_equal "APPROVE", result["decision"]
    assert_equal ["https://legaion.com/terms/"], result["sources"]
  end

  # Nothing retrieved means nothing was verified — recorded, but not a second blocker:
  # the evidence gate already stops a record with no retrieved source.
  test "a page that could not be retrieved is not evidence" do
    blocked = [{ "label" => "website", "url" => "https://www.legaion.com", "status" => "blocked", "reason" => "bot_blocked_403" }]
    result = run_with(approving_output, pages: blocked)

    assert_equal "SKIPPED", result["decision"]
    refute DescriptionVerificationService.blocking?(result), "an absent check is not a verdict"
    assert_equal "skipped", result["mode"]
    assert_empty result["pages_retrieved"]
    assert(result["validation_notes"].any? { |n| n.include?("bot_blocked_403") })
  end

  # ---- corrections --------------------------------------------------------

  test "a revision only carries a correction that clears the publication gate" do
    good = run_with(approving_output(
      "decision" => "REVISE",
      "corrected_description" => "LEGAION is a legal research and contract analysis platform operated by Aidvocates, Inc. for law firms."
    ))
    assert_equal "REVISE", good["decision"]
    assert good["corrected_description"].present?

    promotional = run_with(approving_output(
      "decision" => "REVISE",
      "corrected_description" => "LEGAION is the leading best-in-class legal AI platform trusted by everyone."
    ))
    assert_equal "REVISE", promotional["decision"]
    assert_nil promotional["corrected_description"], "a correction that would fail the gate is not offered"
  end

  # ---- what the publish gate reads ---------------------------------------

  test "manual review and reject block publication; approve and revise do not" do
    assert DescriptionVerificationService.blocking?("decision" => "MANUAL_REVIEW")
    assert DescriptionVerificationService.blocking?("decision" => "REJECT")
    refute DescriptionVerificationService.blocking?("decision" => "APPROVE")
    refute DescriptionVerificationService.blocking?("decision" => "REVISE")
    refute DescriptionVerificationService.blocking?(nil)
  end

  test "an unusable model response never reads as a pass" do
    result = run_with({})

    assert_equal "SKIPPED", result["decision"]
    refute_equal "APPROVE", result["decision"]
    assert_equal "LOW", result["confidence"]
  end
end
