require "timeout"

# Single-call proposal enrichment: one OpenAI Responses API web-search call that
# returns the neutral description, a strictly-sourced founding year, and the full
# taxonomy (category/secondary/business models/target clients/tags) for a proposal.
# This collapses the former three separate LLM calls (research + taxonomy + description)
# into one, reusing the same web-search evidence for all outputs.
#
# Web-search (Responses API) returns text rather than provider-side structured output,
# so the agent renders ProposalEnrichmentSchema's shape into the prompt and parses the
# JSON back, while extracting citation URLs from the raw response for cite-only
# founding-year gating downstream (CompanyProposalEnrichmentService).
class ProposalEnrichmentAgent < RubyLLM::Agent
  DEFAULT_TIMEOUT_SECONDS = 90
  SCHEMA_VERSION = ProposalEnrichmentSchema::SCHEMA_VERSION
  TAXONOMY_CONFIDENCE = 0.9

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(proposal:, site_evidence: nil)
    @proposal = proposal
    @site_evidence = site_evidence
  end

  def call
    return disabled_payload unless enabled?

    result = WebSearchAgent.search(prompt, model: enrichment_model, timeout: timeout_seconds)
    parsed = parse_json_content(result[:content])

    {
      "mode" => "openai_responses_web_search",
      "model" => enrichment_model,
      "schema_version" => SCHEMA_VERSION,
      "proposed_description" => parsed["proposed_description"].to_s.squish.presence,
      "founded_year" => parsed["founded_year"],
      "founded_year_source" => parsed["founded_year_source"],
      "founded_year_evidence_text" => parsed["founded_year_evidence_text"],
      "taxonomy_llm_suggestions" => taxonomy_suggestions(parsed),
      "web_research" => web_research(result[:citations], result[:search_calls], result[:content])
    }
  rescue StandardError => e
    Rails.logger.debug("[ProposalEnrichmentAgent] enrichment failed for proposal #{proposal&.id}: #{e.class}: #{e.message}")
    disabled_payload.merge("mode" => "openai_responses_web_search_error", "error" => e.class.name, "error_message" => e.message)
  end

  private

  attr_reader :proposal, :site_evidence

  def enabled?
    defined?(RubyLLM::ResponsesAPI::BuiltInTools) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("PROPOSAL_ENRICHMENT_USE_LLM", ENV.fetch("DESCRIPTION_DRAFTS_USE_LLM", "true")) == "true"
  end

  def enrichment_model
    ENV.fetch("RUBYLLM_ENRICHMENT_MODEL", ENV.fetch("RUBYLLM_DESCRIPTION_MODEL", ENV.fetch("RUBYLLM_RESEARCH_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))))
  end

  def timeout_seconds
    ENV.fetch("PROPOSAL_ENRICHMENT_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS.to_s).to_i
  end

  def disabled_payload
    {
      "mode" => "disabled_no_responses_web_search",
      "proposed_description" => nil,
      "taxonomy_llm_suggestions" => nil,
      "web_research" => { "mode" => "disabled_no_responses_web_search", "query" => research_query, "results" => [] }
    }
  end

  def taxonomy_suggestions(parsed)
    revenue_models = clean_list(parsed["business_models"])
    target_clients = clean_list(parsed["target_clients"])
    tags = clean_list(parsed["tags"])
    {
      "category_name" => parsed["category"].to_s.strip.presence,
      "category_confidence" => parsed["category"].present? ? TAXONOMY_CONFIDENCE : 0.0,
      "secondary_category_name" => parsed["secondary_category"].to_s.strip.presence,
      "secondary_category_confidence" => parsed["secondary_category"].present? ? TAXONOMY_CONFIDENCE : 0.0,
      "revenue_model_names" => revenue_models,
      "revenue_model_confidence" => revenue_models.any? ? TAXONOMY_CONFIDENCE : 0.0,
      "target_client_name" => target_clients.first,
      "target_client_confidence" => target_clients.any? ? TAXONOMY_CONFIDENCE : 0.0,
      "target_client_names" => target_clients,
      "tag_names" => tags,
      "tags_confidence" => tags.any? ? TAXONOMY_CONFIDENCE : 0.0,
      "mode" => "ruby_llm_single_call"
    }
  end

  def web_research(citations, search_calls, content)
    citation_results = Array(citations).map { |c| result_payload(c["title"], c["url"], c["text"]) }
    call_results = Array(search_calls).flat_map { |call| Array(call[:results] || call["results"]) }.map { |r| result_payload(r[:title] || r["title"], r[:url] || r["url"], r[:snippet] || r["snippet"]) }
    results = (citation_results + call_results).select { |r| r["url"].present? || r["title"].present? }.uniq { |r| r["url"] || r["title"] }.first(8)

    {
      "mode" => "openai_responses_web_search",
      "query" => research_query,
      "summary" => content.to_s.squish.truncate(1000),
      "results" => results,
      "raw_search_call_count" => search_calls.size,
      "generated_at" => Time.current.utc.iso8601
    }
  end

  def result_payload(title, url, snippet)
    { "title" => title.to_s.squish.presence || url, "url" => url, "snippet" => snippet.to_s.squish.presence }.compact
  end

  def clean_list(value)
    Array(value).map { |name| name.to_s.strip }.reject(&:blank?).uniq
  end

  def parse_json_content(content)
    return content if content.is_a?(Hash)

    text = content.to_s.strip
    json_text = text[/\{.*\}/m] || text
    JSON.parse(json_text)
  rescue JSON::ParserError
    {}
  end

  def source_payload
    proposal.source_payload || {}
  end

  def subject_website
    source_payload["website"].presence || proposal.final_changes["main_url"]
  end

  # Text actually retrieved from the company's own site and profiles.
  def retrieved_pages
    SiteEvidenceFetcherService.evidence_text(site_evidence).first(4)
  end

  # Named explicitly so the model is told what could NOT be checked, rather than
  # silently filling the gap from the candidate's self-description.
  def retrieval_failures
    Array(site_evidence && site_evidence["pages"]).reject { |page| page["status"] == "fetched" }
                                                 .map { |page| "#{page['label']}: #{page['status']}#{" (#{page['reason']})" if page['reason'].present?}" }
  end

  def research_query
    [proposal.display_name, subject_website, "legal technology"].compact_blank.join(" ")
  end

  def prompt
    {
      candidate: {
        name: proposal.display_name,
        website: subject_website,
        crunchbase_url: source_payload["crunchbase_url"],
        linkedin_url: source_payload["linkedin_url"],
        location: proposal.final_changes["location"],
        industries: Array(source_payload["industries"]),
        source_short_description: source_payload["source_description"],
        source_full_description: source_payload["full_source_description"]
      },
      retrieved_pages: retrieved_pages,
      retrieval_failures: retrieval_failures,
      allowed_categories: Category.order(:name).pluck(:name),
      allowed_business_models: MethodologyHelper::REVENUE_MODEL_NAMES,
      allowed_target_clients: TaxonomyNormalizationService::CANONICAL_TARGET_CLIENTS,
      allowed_tags: TagTaxonomyService.discoverable_canonical_names,
      instruction: instruction,
      output_shape: output_shape
    }.to_json
  end

  def instruction
    <<~TEXT.squish
      Research this legal-technology company and return a single JSON object (no prose)
      matching output_shape. retrieved_pages holds text fetched from the company's OWN
      site and profiles — treat it as the strongest evidence and prefer it over search
      results and over the candidate's self-description wherever they disagree. Use web
      search to corroborate and to fill gaps. State a product capability ONLY if
      retrieved_pages or a search result supports it; retrieval_failures lists what could
      not be checked, and you must not substitute assumptions for those gaps — write less
      instead. Confirm you are describing the SAME company as the candidate (name and
      domain must agree with the evidence you use); if the evidence is about a different
      company, ignore it rather than blending the two. proposed_description: a neutral, encyclopedic
      directory description of 2-4 sentences (~45-90 words), third person, grounded ONLY in
      what search results show. Cover, when supported: what the company builds and its
      deployment/business model; its core capabilities and the legal workflows it addresses;
      who it serves; and notable named products/integrations. Prefer concrete facts over
      adjectives. Do NOT copy source descriptions verbatim; avoid marketing language,
      superlatives, customer counts, source-meta phrasing, 'web presence' filler, and the
      phrase 'provides or supports'. If evidence is thin, write fewer sentences rather than
      speculate. founded_year: the 4-digit year ONLY if a source explicitly states it (check
      the 'Founded' field on LinkedIn/Crunchbase and official registries such as
      OpenCorporates or national registries; prefer an official registry over a self-reported
      profile if they disagree), else null — never guess. founded_year_source: the exact URL
      from search results that states it, else null. founded_year_evidence_text: a short
      verbatim snippet from that source naming THIS company and stating the year, else null.
      Classify using ONLY the controlled vocabulary: category and optional distinct
      secondary_category from allowed_categories; business_models (1-2) from
      allowed_business_models;       target_clients (1-2) from allowed_target_clients; and tags — include EVERY
      applicable keyword from allowed_tags (aim for 2-4 on a feature-rich company; e.g.
      a case-management tool that also offers e-signature should get both), preferring
      specific capability tags and avoiding the generic "technology"/"innovation" unless
      nothing more specific applies. Use only allowed_tags. Never invent taxonomy or tag values.
    TEXT
  end

  def output_shape
    {
      "proposed_description" => "string",
      "founded_year" => "YYYY or null",
      "founded_year_source" => "url or null",
      "founded_year_evidence_text" => "snippet or null",
      "category" => "one of allowed_categories or null",
      "secondary_category" => "one of allowed_categories or null",
      "business_models" => ["from allowed_business_models"],
      "target_clients" => ["from allowed_target_clients"],
      "tags" => ["from allowed_tags"]
    }
  end
end
