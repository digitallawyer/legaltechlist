require "timeout"

class UserSuggestionInterpretationService
  FIELD_KEYS = CompanyProposal::EDITABLE_COMPANY_FIELDS

  def self.call(proposal:)
    new(proposal: proposal).call
  end

  def initialize(proposal:)
    @proposal = proposal
  end

  def call
    return deterministic_delta if deterministic_delta.any?
    return llm_delta if llm_enabled?

    {}
  end

  private

  attr_reader :proposal

  def deterministic_delta
    delta = {}
    message = proposal.user_message.to_s
    issue_type = proposal.issue_type.to_s

    if issue_type == "broken_link" && proposal.source_payload["source_url"].present?
      delta["main_url"] = proposal.source_payload["source_url"] if message.match?(/website|homepage|main url/i)
      delta["linkedin_url"] = proposal.source_payload["source_url"] if message.match?(/linkedin/i)
      delta["crunchbase_url"] = proposal.source_payload["source_url"] if message.match?(/crunchbase/i)
    end

    founded_match = message.match(/\b(19|20)\d{2}\b/)
    delta["founded_date"] = founded_match[0] if issue_type.in?(%w[incorrect_details]) && founded_match

    if message.match?(/\bdescription\b/i)
      description_match = message.match(/\b(?:update|change|set|correct)\s+(?:the\s+)?description\s+to\s+(.+)/i) ||
        message.match(/\bdescription\s+should\s+be\s+(.+)/i)
      proposed_description = description_match&.[](1).to_s.strip
      delta["description"] = proposed_description if proposed_description.present?
    end

    delta.slice(*FIELD_KEYS)
  end

  def llm_delta
    SuggestionInterpretationAgent.call(proposal: proposal, field_keys: FIELD_KEYS)
  end

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("USER_SUGGESTION_INTERPRET_USE_LLM", Rails.env.production? ? "true" : "false") == "true"
  end
end
