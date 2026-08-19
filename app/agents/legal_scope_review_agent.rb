require "timeout"

# LLM reviewer that decides whether an Unknown-category company belongs in the
# legal-technology index and, if so, its best category. Returns structured output
# (or nil when disabled/failed); CompanyLegalScopeReviewService applies the actions
# and confidence gating. Cheap-model tier (bounded classification).
class LegalScopeReviewAgent < RubyLLM::Agent
  model "gpt-5.4-nano"
  schema LegalScopeReviewSchema
  temperature 0.1

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company:)
    @company = company
  end

  def call
    return nil unless enabled?

    chat = self.class.chat(model: llm_model, provider: :openai, assume_model_exists: unknown_model?(llm_model))
    response = Timeout.timeout(timeout_seconds) { chat.ask(prompt) }
    parsed = parse_json_content(response.content)
    return nil unless parsed.is_a?(Hash)

    parsed.merge("mode" => "ruby_llm")
  rescue StandardError => e
    Rails.logger.debug("[LegalScopeReviewAgent] failed: #{e.class}: #{e.message}")
    nil
  end

  private

  attr_reader :company

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
      company: {
        name: company.name,
        website: company.main_url,
        description: effective_description,
        target_clients: company.audience_names,
        tags: company.tags.map(&:name)
      },
      allowed_category_names: Category.where.not(name: "Unknown").order(:name).pluck(:name),
      instruction: "Decide whether this profile belongs in a legal-technology company index. A legal technology company is a market-facing vendor whose principal business is software, data, or technology-enabled services for legal work. If legal-tech, pick the best category_name from allowed_category_names, else null. All confidences are 0.0-1.0."
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
