# Structured contract for the single-call proposal enrichment pass. The enrichment
# runs over the OpenAI Responses API with the hosted web_search tool (which returns
# text, not provider-side structured output), so ProposalEnrichmentAgent renders this
# shape into the prompt and parses the JSON back. Keeping the contract here gives a
# single source of truth and a version marker for the merged description + founded
# year + taxonomy + tags payload that replaces the former 3 separate LLM calls.
# (Documentation contract only — not passed as a strict schema, so nullable fields are
# fine here; "no value" is expressed as null in the parsed JSON.)
class ProposalEnrichmentSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-07-02.1".freeze

  string :proposed_description, description: "Neutral, encyclopedic directory description, 2-4 sentences (~45-90 words), grounded only in evidence; no marketing language."
  string :founded_year, required: false, description: "4-digit founding year ONLY if a source explicitly states it, else null."
  string :founded_year_source, required: false, description: "Exact source URL that states the founded_year, else null."
  string :founded_year_evidence_text, required: false, description: "Verbatim snippet naming THIS company and stating the year, else null."
  string :category, required: false, description: "One primary category, exactly from allowed_categories, or null."
  string :secondary_category, required: false, description: "Optional distinct second category from allowed_categories (must differ from category), or null."
  array :business_models, of: :string, description: "1-2 revenue models exactly from allowed_business_models."
  array :target_clients, of: :string, description: "1-2 client types exactly from allowed_target_clients."
  array :tags, of: :string, description: "0-4 keywords exactly from allowed_tags, or empty."
end
