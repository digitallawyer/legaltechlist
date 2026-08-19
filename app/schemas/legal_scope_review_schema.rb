# Structured output for deciding whether an Unknown-category company belongs in a
# legal-technology index and, if so, its best category. Applied downstream by
# CompanyLegalScopeReviewService with confidence gating.
# All fields required (OpenAI strict structured outputs); empty string = no category.
class LegalScopeReviewSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-07-02.2".freeze

  boolean :is_legal_technology, description: "Whether this is a market-facing legal-technology company."
  string :category_name, description: "Best primary category from allowed_category_names if legal-tech, else empty string."
  number :category_confidence, description: "0.0-1.0 confidence in the category (0 if none)."
  number :confidence, description: "0.0-1.0 overall confidence in the legal-tech determination."
  string :reason, description: "Short justification."
end
