# Structured output for taxonomy classification (category/secondary/business models/
# target clients/tags) from candidate evidence. Names are validated against the
# controlled vocabulary downstream in CompanyProposalTaxonomySuggestionService.
#
# NOTE: OpenAI strict structured outputs require EVERY property to be listed in
# `required`, so all fields are required. "No value" is expressed as an empty string
# / empty array / 0.0 confidence, which the downstream mapping treats as absent.
class TaxonomySuggestionSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-07-02.2".freeze

  string :category_name, description: "Primary category, exactly from allowed_category_names (empty string if unknown)."
  number :category_confidence, description: "0.0-1.0 confidence in the primary category."
  string :secondary_category_name, description: "Distinct secondary category from allowed_category_names, or empty string if none."
  number :secondary_category_confidence, description: "0.0-1.0 confidence in the secondary category (0 if none)."
  array :revenue_model_names, of: :string, description: "1-3 revenue models from allowed_revenue_model_names."
  number :revenue_model_confidence, description: "0.0-1.0 confidence in the revenue models."
  string :target_client_name, description: "Primary target client from allowed_target_client_names (empty string if unknown)."
  number :target_client_confidence, description: "0.0-1.0 confidence in the target client."
  array :target_client_names, of: :string, description: "1-3 target clients from allowed_target_client_names."
  array :tag_names, of: :string, description: "0-5 tags from preferred_tag_vocabulary only (empty if none)."
  number :tags_confidence, description: "0.0-1.0 confidence in the tags (0 if none)."
end
