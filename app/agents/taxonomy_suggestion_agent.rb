require "timeout"

# LLM taxonomy classifier: suggests category/secondary/business models/target
# clients/tags for a candidate from its evidence, as structured output. Returns a
# plain hash (or nil when disabled/failed) so CompanyProposalTaxonomySuggestionService
# maps names->ids and applies confidence/accepted rules and a deterministic fallback.
# Taxonomy is a constrained classification task, so it routes to a cheaper model tier.
class TaxonomySuggestionAgent < RubyLLM::Agent
  model "gpt-5.4-nano"
  schema TaxonomySuggestionSchema
  temperature 0.1

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(source_payload:, final_changes: {})
    @source_payload = source_payload || {}
    @final_changes = final_changes || {}
  end

  def call
    return nil unless enabled?

    chat = self.class.chat(model: llm_model, provider: :openai, assume_model_exists: unknown_model?(llm_model))
    response = Timeout.timeout(timeout_seconds) { chat.ask(prompt) }
    parsed = parse_json_content(response.content)
    return nil unless parsed.is_a?(Hash)

    parsed["revenue_model_names"] ||= Array(parsed["business_model_name"]).compact
    parsed["target_client_names"] ||= Array(parsed["target_client_name"]).compact
    parsed["tag_names"] ||= []
    parsed.merge("mode" => "ruby_llm")
  rescue StandardError => e
    Rails.logger.debug("[TaxonomySuggestionAgent] failed: #{e.class}: #{e.message}")
    nil
  end

  private

  attr_reader :source_payload, :final_changes

  def enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("PROPOSAL_TAXONOMY_USE_LLM", Rails.env.production? ? "true" : "false") == "true"
  end

  def llm_model
    ENV.fetch("RUBYLLM_TAXONOMY_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def timeout_seconds
    ENV.fetch("PROPOSAL_TAXONOMY_TIMEOUT_SECONDS", "45").to_i
  end

  def prompt
    {
      candidate: source_payload.slice("name", "industries", "source_description", "full_source_description", "website"),
      allowed_category_names: Category.order(:name).pluck(:name),
      allowed_revenue_model_names: MethodologyHelper::REVENUE_MODEL_NAMES,
      allowed_target_client_names: TaxonomyNormalizationService::CANONICAL_TARGET_CLIENTS,
      preferred_tag_vocabulary: TagTaxonomyService.discoverable_canonical_names,
      instruction: "Classify this legal-technology company. Use only allowed names for categories, revenue models, and target clients. secondary_category_name is optional and must differ from the primary. tag_names must come only from preferred_tag_vocabulary (1-5) and must not duplicate the structured taxonomy. All confidences are 0.0-1.0."
    }.to_json
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
