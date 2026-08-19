require "timeout"

# LLM interpreter that turns a free-text user suggestion into a proposed_changes field
# map when deterministic parsing didn't resolve it. Returns the raw proposed_changes
# hash (the caller slices it to the editable-field allowlist). No structured schema is
# used here because the output is a dynamic field->value map (mixed value types), which
# does not fit a fixed strict schema; the field allowlist is enforced by the caller.
# Cheapest model tier (nano).
class SuggestionInterpretationAgent < RubyLLM::Agent
  model "gpt-5.4-nano"

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:, field_keys:)
    @proposal = proposal
    @field_keys = field_keys
  end

  def call
    return {} unless enabled?

    chat = self.class.chat(model: llm_model, provider: :openai, assume_model_exists: unknown_model?(llm_model))
    response = Timeout.timeout(timeout_seconds) { chat.ask(prompt) }
    parsed = parse_json_content(response.content)
    changes = parsed.is_a?(Hash) && parsed["proposed_changes"].is_a?(Hash) ? parsed["proposed_changes"] : {}
    changes.slice(*field_keys)
  rescue StandardError => e
    Rails.logger.debug("[SuggestionInterpretationAgent] failed: #{e.class}: #{e.message}")
    {}
  end

  private

  attr_reader :proposal, :field_keys

  def enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("USER_SUGGESTION_INTERPRET_USE_LLM", Rails.env.production? ? "true" : "false") == "true"
  end

  def llm_model
    ENV.fetch("RUBYLLM_TRIAGE_MODEL", "gpt-5.4-nano")
  end

  def timeout_seconds
    ENV.fetch("USER_SUGGESTION_INTERPRET_TIMEOUT_SECONDS", "20").to_i
  end

  def prompt
    current = proposal.proposed_changes.slice(*field_keys)
    <<~PROMPT
      Parse a user suggestion for a legal-tech company directory into field updates.
      Return JSON only: {"proposed_changes": {field: value}}
      Allowed fields: #{field_keys.join(', ')}
      Issue type: #{proposal.issue_type}
      User message: #{proposal.user_message}
      Supporting URL: #{proposal.source_payload['source_url']}
      Current values: #{current.to_json}
      Only include fields that should change based on the message.
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
