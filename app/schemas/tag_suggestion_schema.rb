# Structured output for tag suggestions on a company, drawn from the discoverable
# tag vocabulary. Validated/normalized downstream in TagSuggestionService.
# All fields required (OpenAI strict structured outputs); empty array = no tags.
class TagSuggestionSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-07-02.2".freeze

  array :tag_names, of: :string, description: "0-5 lowercase technology/theme keywords from preferred_tag_vocabulary only (empty if none fit)."
  number :confidence, description: "0.0-1.0 confidence in the suggested tags (0 if none)."
end
