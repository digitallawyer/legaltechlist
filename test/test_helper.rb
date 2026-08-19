ENV['RAILS_ENV'] ||= 'test'
ENV["DESCRIPTION_DRAFTS_USE_LLM"] ||= "false"
ENV["PROPOSAL_WEB_SEARCH_USE_RESPONSES"] ||= "false"
ENV["USER_SUBMISSION_TRIAGE_USE_LLM"] ||= "false"
ENV["USER_SUGGESTION_INTERPRET_USE_LLM"] ||= "false"
ENV["USER_SUGGESTION_AUTO_APPLY"] ||= "false"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'minitest/mock'

# Never deliver real Slack messages from the test suite. Delivery is only enabled
# inside `with_slack_delivery { ... }`, for tests that explicitly exercise Slack.
module SlackNotifierTestSilence
  def post_message(*args, **kwargs)
    Thread.current[:allow_slack_delivery] ? super : nil
  end

  def post_thread(*args, **kwargs)
    Thread.current[:allow_slack_delivery] ? super : nil
  end
end
SlackNotifier.singleton_class.prepend(SlackNotifierTestSilence)

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Allow real SlackNotifier delivery within the block (still respects env config).
  def with_slack_delivery
    previous = Thread.current[:allow_slack_delivery]
    Thread.current[:allow_slack_delivery] = true
    yield
  ensure
    Thread.current[:allow_slack_delivery] = previous
  end

  # A proposal is only publishable once something was actually retrieved for it (see
  # CompanyProposalQualityService#unverified_blocker). Tests whose subject is the
  # publish path, rather than the evidence gate itself, use this to build a
  # realistically researched record instead of one that merely has its fields filled.
  def researched_agent_details(url:, extra: {})
    {
      "site_evidence" => {
        "mode" => "http_fetch",
        "pages" => [{
          "label" => "website", "url" => url, "final_url" => url, "status" => "fetched",
          "title" => "Company", "text" => "Product pages describing the company's legal software."
        }]
      }
    }.deep_merge(extra)
  end

  # Stamp an existing proposal as researched, for paths that create it out of reach.
  def mark_researched!(proposal, url: nil)
    target = url || proposal.editable_changes["main_url"] || "https://example.com"
    proposal.update!(enriched_at: Time.current, agent_details: proposal.agent_details.deep_merge(researched_agent_details(url: target)))
    proposal
  end

  # Enrichment retrieves the candidate's own site (SiteEvidenceFetcherService), and no
  # test touches the network. Wrap a block in this when the subject under test is the
  # pipeline around enrichment rather than the retrieval itself, so records come out
  # verified the way they do in production. The stand-in domain is deliberately inert so
  # it cannot collide with a fixture company and fake a duplicate match.
  def with_site_evidence(url: "https://site-evidence.test", &block)
    SiteEvidenceFetcherService.stub(:call, researched_agent_details(url: url)["site_evidence"], &block)
  end

  # Add more helper methods to be used by all tests here...
end
