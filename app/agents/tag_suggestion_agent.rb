require "timeout"

# LLM tag suggester for a published company (hygiene/backfill). Returns structured
# tag_names + confidence; TagSuggestionService normalizes, filters to the assignable
# vocabulary, and applies the confidence gate. Cheap-model tier (constrained keywords).
class TagSuggestionAgent < RubyLLM::Agent
  model "gpt-5.4-nano"
  schema TagSuggestionSchema
  temperature 0.1

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company:, max_tags: 5)
    @company = company
    @max_tags = max_tags
  end

  def call
    return { "tag_names" => [], "confidence" => 0.0, "mode" => "llm_disabled" } unless enabled?

    chat = self.class.chat(model: llm_model, provider: :openai, assume_model_exists: unknown_model?(llm_model))
    response = Timeout.timeout(timeout_seconds) { chat.ask(prompt) }
    parsed = parse_json_content(response.content)
    return { "tag_names" => [], "confidence" => 0.0, "mode" => "ruby_llm_error" } unless parsed.is_a?(Hash)

    parsed.merge("mode" => "ruby_llm")
  rescue StandardError => e
    Rails.logger.debug("[TagSuggestionAgent] failed: #{e.class}: #{e.message}")
    { "tag_names" => [], "confidence" => 0.0, "mode" => "ruby_llm_error" }
  end

  private

  attr_reader :company, :max_tags

  def enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("TAG_SUGGESTION_USE_LLM", ENV.fetch("PROPOSAL_TAXONOMY_USE_LLM", Rails.env.production? ? "true" : "false")) == "true"
  end

  def llm_model
    ENV.fetch("RUBYLLM_TAXONOMY_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def timeout_seconds
    ENV.fetch("TAG_SUGGESTION_TIMEOUT_SECONDS", ENV.fetch("PROPOSAL_TAXONOMY_TIMEOUT_SECONDS", "45")).to_i
  end

  def prompt
    {
      company: {
        name: company.name,
        website: company.main_url,
        description: effective_description,
        category: company.category&.name,
        target_clients: company.audience_names
      },
      preferred_tag_vocabulary: TagTaxonomyService.discoverable_canonical_names,
      instruction: "Suggest every applicable lowercase technology or theme keyword for this legal-technology company (aim for 2-#{max_tags} on a feature-rich company) using only terms from preferred_tag_vocabulary. Prefer specific capability keywords; avoid the generic 'technology' and 'innovation' unless nothing more specific applies. Do not repeat category, revenue model, or target client information — those are captured elsewhere. confidence is 0.0-1.0."
    }.to_json
  end

  def effective_description
    text = company.description.to_s.strip
    return nil if text.blank? || text == "No description yet"

    text
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
