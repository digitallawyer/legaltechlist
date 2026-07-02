# Structured output for tag suggestions on a company, drawn from the discoverable
# tag vocabulary. Validated/normalized downstream in TagSuggestionService.
class TagSuggestionSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-07-02.1".freeze

  array :tag_names, of: :string, description: "1-5 lowercase technology/theme keywords from preferred_tag_vocabulary only."
  number :confidence, required: false, description: "0.0-1.0 confidence in the suggested tags."
end
