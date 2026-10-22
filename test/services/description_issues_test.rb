require "test_helper"

class DescriptionIssuesTest < ActiveSupport::TestCase
  def issues(text) = CompanyProposalEnrichmentService.description_issues(text)

  CLEAN = "Acme builds contract review software for in-house legal teams, covering clause extraction, playbook comparison and redlining across Word documents and common document management systems."

  test "a plain factual description passes" do
    assert_empty issues(CLEAN)
  end

  test "hedges, prices, offers, the first and second person, and plans are each flagged" do
    assert_match(/hedges/, issues(CLEAN.sub("builds", "appears to build")).join)
    assert_match(/hedges/, issues(CLEAN.sub("builds", "aims to build")).join)
    assert_match(/pricing/, issues("#{CLEAN} Plans start at $49 per month.").join)
    assert_match(/pricing/, issues("#{CLEAN} Request a demo today.").join)
    assert_match(/third person/, issues("#{CLEAN.sub('Acme builds', 'We build')}").join)
    assert_match(/plans or a waitlist/, issues("#{CLEAN} A public waitlist is open.").join)
  end

  test "a long entry is flagged, and a real name containing a word does not trigger" do
    assert_match(/longer/, issues(([CLEAN] * 6).join(" ")).join)
    assert_empty issues(CLEAN.sub("Acme", "Acme, a US-based company,").sub("builds", "builds legal pricing and matter budgeting"))
    assert_empty issues("Usable builds contract review software for in-house legal teams, covering clause extraction, playbook comparison and redlining across Word documents and common document management systems.")
  end

  test "a description that reports what a page says instead of what the company does is flagged" do
    [
      "Tahsico's website states that the company is developing a new offering. The site does not identify the offering or describe its capabilities.",
      "InteliLex is named in a plan to merge SoftwareHut sp. z o.o., ExtraHut sp. z o.o., and InteliLex sp. z o.o. as part of a restructuring.",
      "eChamber is presented as Pakistan's first AI-powered legal management system. The official site identifies it as a legal-management product.",
      "Search-result text from the official site says users can access legal databases and draft documents with the assistant on the device.",
      "Salmo Visa describes its offering as a personalised visa experience for individuals and families seeking to relocate abroad."
    ].each { |text| assert_match(/what a website, search result or filing says/, issues(text).join, text) }
    assert_empty issues("Ocaflow provides Brazilian companies with tools for managing shareholder contracts, incentive programs, equity plans and cap table information in real time.")
  end
end
