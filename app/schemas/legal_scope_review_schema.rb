# Structured output for deciding whether an Unknown-category company belongs in a
# legal-technology index and, if so, its best category. Applied downstream by
# CompanyLegalScopeReviewService with confidence gating.
class LegalScopeReviewSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-07-02.1".freeze

  boolean :is_legal_technology, description: "Whether this is a market-facing legal-technology company."
  string :category_name, required: false, description: "Best primary category from allowed_category_names if legal-tech, else null."
  number :category_confidence, required: false, description: "0.0-1.0 confidence in the category."
  number :confidence, required: false, description: "0.0-1.0 overall confidence in the legal-tech determination."
  string :reason, required: false, description: "Short justification."
end
