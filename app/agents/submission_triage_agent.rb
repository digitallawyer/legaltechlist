require "timeout"

# LLM triage for public directory submissions that deterministic rules didn't decide.
# Returns a structured verdict (or nil when disabled/failed); UserSubmissionTriageService
# wraps it into the standard verdict payload. Cheapest model tier (nano).
class SubmissionTriageAgent < RubyLLM::Agent
  model "gpt-5.4-nano"
  schema SubmissionTriageSchema
  temperature 0.1

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:)
    @proposal = proposal
  end

  def call
    return nil unless enabled?

    chat = self.class.chat(model: llm_model, provider: :openai, assume_model_exists: unknown_model?(llm_model))
    response = Timeout.timeout(timeout_seconds) { chat.ask(prompt) }
    parsed = parse_json_content(response.content)
    parsed.is_a?(Hash) ? parsed : nil
  rescue StandardError => e
    Rails.logger.debug("[SubmissionTriageAgent] failed: #{e.class}: #{e.message}")
    nil
  end

  private

  attr_reader :proposal

  def enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("USER_SUBMISSION_TRIAGE_USE_LLM", Rails.env.production? ? "true" : "false") == "true"
  end

  def llm_model
    ENV.fetch("RUBYLLM_TRIAGE_MODEL", "gpt-5.4-nano")
  end

  def timeout_seconds
    ENV.fetch("USER_SUBMISSION_TRIAGE_TIMEOUT_SECONDS", "20").to_i
  end

  def prompt
    <<~PROMPT
      You triage public legal-tech directory submissions. Decide accept, review, or reject.

      Proposal type: #{proposal.proposal_type}
      Company name: #{proposal.final_changes['name']}
      Website: #{proposal.final_changes['main_url']}
      Description: #{proposal.final_changes['description']}
      User message: #{proposal.user_message}
      Duplicate domain signals: #{proposal.duplicate_signals['domain_matches'].to_json}
    PROMPT
  end

  def parse_json_content(content)
    return content if content.is_a?(Hash)

    JSON.parse(content.to_s)
  rescue JSON::ParserError
    nil
  end

  def unknown_model?(model)
    RubyLLM.models.find(model)
    false
  rescue RubyLLM::ModelNotFoundError
    true
  end
end
