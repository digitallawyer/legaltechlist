# Structured output for taxonomy classification (category/secondary/business models/
# target clients/tags) from candidate evidence. Names are validated against the
# controlled vocabulary downstream in CompanyProposalTaxonomySuggestionService.
class TaxonomySuggestionSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-07-02.1".freeze

  string :category_name, required: false, description: "Primary category, exactly from allowed_category_names, or null."
  number :category_confidence, required: false, description: "0.0-1.0 confidence in the primary category."
  string :secondary_category_name, required: false, description: "Optional distinct secondary category from allowed_category_names, or null."
  number :secondary_category_confidence, required: false, description: "0.0-1.0 confidence in the secondary category."
  array :revenue_model_names, of: :string, description: "1-3 revenue models from allowed_revenue_model_names."
  number :revenue_model_confidence, required: false, description: "0.0-1.0 confidence in the revenue models."
  string :target_client_name, required: false, description: "Primary target client from allowed_target_client_names, or null."
  number :target_client_confidence, required: false, description: "0.0-1.0 confidence in the target client."
  array :target_client_names, of: :string, description: "1-3 target clients from allowed_target_client_names."
  array :tag_names, of: :string, description: "1-5 tags from preferred_tag_vocabulary only."
  number :tags_confidence, required: false, description: "0.0-1.0 confidence in the tags."
end
