require "timeout"

class CompanyDiscoverySearchService
  DISCOVERY_TYPES = %w[category competitors year country funding_year].freeze
  DEFAULT_TIMEOUT_SECONDS = 180
  EMPTY_RESULT_RETRY_BACKOFF_SECONDS = 3
  # Web search occasionally throws a transient "execution expired"/timeout or an
  # upstream 5xx/rate-limit. Retry a couple of times with linear backoff so a blip
  # doesn't fail the whole discovery run and require a manual re-fire.
  TRANSIENT_SEARCH_RETRIES = 2
  TRANSIENT_SEARCH_BACKOFF_SECONDS = 5
  TRANSIENT_SEARCH_ERROR_PATTERN = /execution expired|timed?\s?out|timeout|temporarily unavailable|rate.?limit|too many requests|\b50[234]\b|connection reset|econnreset|econnrefused/i

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(discovery_type:, context:, exclusion_list:, limit:, search_client: nil)
    @discovery_type = discovery_type.to_s
    @context = context
    @exclusion_list = exclusion_list
    @limit = limit.to_i
    @search_client_override = search_client
  end

  def call
    return disabled_payload unless web_search_enabled?

    payload = perform_search_with_retry
    log_empty_result_outcome(payload)
    payload
  rescue StandardError => e
    disabled_payload.merge(
      "mode" => "openai_responses_web_search_error",
      "error" => e.class.name,
      "error_message" => e.message
    )
  end

  private

  attr_reader :discovery_type, :context, :exclusion_list, :limit

  def web_search_enabled?
    @search_client_override.present? || (
      defined?(RubyLLM::ResponsesAPI::BuiltInTools) &&
        ENV["OPENAI_API_KEY"].present? &&
        ENV.fetch("DISCOVERY_USE_WEB_SEARCH", "true") == "true"
    )
  end

  def resolved_search_client
    @resolved_search_client ||= @search_client_override || default_search_client
  end

  def default_search_client
    return nil unless web_search_enabled?

    lambda do |prompt|
      result = WebSearchAgent.search(prompt, model: research_model, timeout: llm_timeout_seconds)
      result.slice(:content, :search_urls, :raw_search_call_count)
    end
  end

  def disabled_payload
    {
      "mode" => "disabled_no_responses_web_search",
      "discovery_type" => discovery_type,
      "query" => search_query,
      "companies" => [],
      "note" => "OpenAI Responses API web search is disabled or unavailable."
    }
  end

  def research_model
    ENV.fetch("RUBYLLM_DISCOVERY_MODEL", ENV.fetch("RUBYLLM_RESEARCH_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5")))
  end

  def llm_timeout_seconds
    ENV.fetch("DISCOVERY_TIMEOUT_SECONDS", ENV.fetch("PROPOSAL_RESEARCH_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS.to_s)).to_i
  end

  def perform_search_with_retry
    response = call_search_client(search_prompt)
    payload = build_search_payload(response)
    return payload if payload["companies"].any? || payload["error_message"].present?

    sleep(EMPTY_RESULT_RETRY_BACKOFF_SECONDS)
    retry_response = call_search_client(search_prompt)
    retry_payload = build_search_payload(retry_response)
    retry_payload.merge(
      "empty_result_retry" => true,
      "discovered_count_before_retry" => 0,
      "retry_discovered_count" => retry_payload["companies"].size
    )
  end

  # Invoke the web-search client, retrying on transient errors (timeouts, upstream
  # 5xx/rate-limits) with linear backoff before letting the error propagate.
  def call_search_client(prompt)
    attempts = 0
    begin
      resolved_search_client.call(prompt)
    rescue StandardError => e
      attempts += 1
      raise unless attempts <= transient_search_retries && transient_search_error?(e)

      Rails.logger.debug("[CompanyDiscoverySearchService] transient web-search error (#{e.class}: #{e.message}); retry #{attempts}/#{transient_search_retries} after backoff")
      sleep(TRANSIENT_SEARCH_BACKOFF_SECONDS * attempts)
      retry
    end
  end

  def transient_search_retries
    ENV.fetch("DISCOVERY_SEARCH_RETRIES", TRANSIENT_SEARCH_RETRIES.to_s).to_i
  end

  def transient_search_error?(error)
    error.is_a?(Timeout::Error) || error.message.to_s.match?(TRANSIENT_SEARCH_ERROR_PATTERN)
  end

  def build_search_payload(response)
    parsed = parse_companies_json(response[:content])
    search_urls = Array(response[:search_urls])
    companies = Array(parsed["companies"]).first(limit).filter_map { |company| build_company_payload(company, search_urls) }

    {
      "mode" => "openai_responses_web_search",
      "discovery_type" => discovery_type,
      "query" => search_query,
      "companies" => companies,
      "raw_search_call_count" => response[:raw_search_call_count],
      "generated_at" => Time.current.utc.iso8601
    }
  end

  def log_empty_result_outcome(payload)
    return if payload["error_message"].present?

    count = Array(payload["companies"]).size
    if count.zero?
      Rails.logger.debug("[CompanyDiscoverySearchService] discovery_type=#{discovery_type} returned 0 companies query=#{search_query} retry=#{payload['empty_result_retry'] || false}")
    end
  end

  def search_query
    case discovery_type
    when "category"
      "legal technology companies in #{context.fetch(:category)} category"
    when "competitors"
      "competitors and alternatives to #{context.fetch(:company_name)} legal technology"
    when "year"
      "legal technology companies founded in #{context.fetch(:year)}"
    when "country"
      "legal technology companies headquartered in #{context.fetch(:country)}"
    when "funding_year"
      "legal technology companies that raised funding in #{context.fetch(:funding_year)}"
    else
      "legal technology companies"
    end
  end

  def search_prompt
    <<~PROMPT
      You are discovering legal-technology companies for the Stanford CodeX TechIndex directory.

      Discovery task: #{search_query}
      #{discovery_task_guidance}
      Return up to #{limit} distinct companies not already listed in TechIndex.

      Exclude these existing index entries (name or domain):
      #{formatted_exclusion_list}

      Use web search to find real, market-facing legal technology vendors.
      Only include companies whose official website appears in search results.
      Do not invent URLs, funding figures, or company details.

      For each company also classify it using ONLY the controlled vocabulary below,
      and capture a founding year only if a source documents it:
      #{allowed_taxonomy_guidance}#{tag_guidance}
      For founded_year_source, give the exact URL from search results that explicitly
      documents the founding year (e.g. the company's LinkedIn/Crunchbase "Founded" field
      or an official registry). If you cannot find a source that states the founding year,
      set BOTH founded_date and founded_year_source to null. Never guess a founding year,
      and do not use a page that does not actually show the year as its source.

      For description, write a neutral, encyclopedic directory description of 2-4 sentences
      (about 45-90 words) in the third person, grounded only in what search results show.
      When the evidence supports it, cover: (1) what the company builds and its deployment or
      business model (e.g. cloud-based platform, marketplace, managed service); (2) its core
      capabilities and the legal workflows it addresses; (3) who it serves (law firms,
      corporate/in-house legal teams, specific practice areas or industries); and (4) notable
      named products/modules and integrations. Use concrete product/function facts, not
      adjectives. It must be fit for an academic directory: no marketing language, no
      superlatives, no customer counts, no "leading" or "innovative", no "web presence"
      filler, and no first-person or promotional phrasing. Do not copy a company's own tagline
      verbatim; describe the function plainly. If evidence is thin, write fewer sentences
      rather than padding with speculation.

      Return JSON only with this shape:
      #{json_output_schema}
    PROMPT
  end

  def discovery_task_guidance
    case discovery_type
    when "year"
      "Focus on legal-tech vendors founded in #{context.fetch(:year)}. Prefer companies whose founding year is documented in search results."
    when "country"
      "Focus on legal-tech vendors headquartered in #{context.fetch(:country)}. Prefer companies with a clear HQ location in that country."
    when "funding_year"
      <<~GUIDANCE.squish
        Focus on commercial legal-tech vendors (software/platforms sold to law firms, corporate legal teams, or legal departments) that raised venture or growth funding in #{context.fetch(:funding_year)}.
        Include only companies where the funding round year is documented in search results.
        Exclude nonprofits, legal-aid organizations, advocacy groups, and companies already well-covered in TechIndex.
        Prefer net-new vendors not already in the exclusion list; avoid repeating the same well-known incumbents.
      GUIDANCE
    else
      ""
    end
  end

  # Tags + secondary category are gated by DISCOVERY_INCLUDE_TAGS so the richer
  # discovery output can be toggled off during bake-in without touching the code path.
  def include_taxonomy_extras?
    ENV.fetch("DISCOVERY_INCLUDE_TAGS", "true") == "true"
  end

  def taxonomy_schema_fields
    extras = if include_taxonomy_extras?
      <<~EXTRAS.strip
        "secondary_category": "Optional distinct second category EXACTLY from allowed_categories (must differ from category), or null",
              "tags": ["0-4 keywords EXACTLY from allowed_tags, or an empty list"],
      EXTRAS
    else
      ""
    end

    <<~FIELDS.strip
      "category": "One primary category, EXACTLY from allowed_categories, or null",
            #{extras}"business_models": ["1-2 revenue models EXACTLY from allowed_business_models"],
            "target_clients": ["1-2 client types EXACTLY from allowed_target_clients"],
            "founded_year_source": "URL from search results documenting the founding year, or null"
    FIELDS
  end

  def tag_guidance
    return "" unless include_taxonomy_extras?

    "\n" + <<~GUIDANCE.strip
      Assign a secondary_category ONLY when a clearly distinct second category also
      applies; otherwise set it to null. For tags, include EVERY applicable keyword
      from allowed_tags — aim for 2-4 on a feature-rich company (e.g. a case-management
      tool that also offers e-signature should get BOTH "case management" and
      "e-signature"). Prefer specific capability tags; avoid the generic "technology"
      and "innovation" unless nothing more specific applies. Use only allowed_tags,
      never invent tags, and return fewer only when the evidence genuinely supports it.
    GUIDANCE
  end

  def json_output_schema
    base_fields = <<~FIELDS.strip
      "name": "Company Name",
            "website": "https://example.com",
            "location": "City, Country",
            "founded_date": "2018",
            "description": "Neutral, encyclopedic directory description of 2-4 sentences (~45-90 words) covering the company's product, capabilities, who it serves, and notable products/integrations; no marketing language.",
            "why_discovered": "Short reason this company matches the discovery task.",
            #{taxonomy_schema_fields}
    FIELDS

    funding_fields = <<~FIELDS.strip
      "name": "Company Name",
            "website": "https://example.com",
            "location": "City, Country",
            "founded_date": "2018",
            "description": "Neutral, encyclopedic directory description of 2-4 sentences (~45-90 words) covering the company's product, capabilities, who it serves, and notable products/integrations; no marketing language.",
            "why_discovered": "Short reason this company matches the discovery task.",
            "funding_round_year": "2024",
            "funding_round_type": "Series A",
            "funding_amount_hint": "Optional amount or range if documented in search results.",
            #{taxonomy_schema_fields}
    FIELDS

    fields = discovery_type == "funding_year" ? funding_fields : base_fields

    <<~SCHEMA.strip
      {
        "companies": [
          {
            #{fields}
          }
        ]
      }
    SCHEMA
  end

  def allowed_taxonomy_guidance
    <<~GUIDANCE.strip
      allowed_categories: #{Category.order(:name).pluck(:name).join(', ')}
      allowed_business_models: #{MethodologyHelper::REVENUE_MODEL_NAMES.join(', ')}
      allowed_target_clients: #{TaxonomyNormalizationService::CANONICAL_TARGET_CLIENTS.join(', ')}#{include_taxonomy_extras? ? "\n      allowed_tags: #{TagTaxonomyService.discoverable_canonical_names.join(', ')}" : ''}
    GUIDANCE
  end

  def formatted_exclusion_list
    names = Array(exclusion_list["names"]).first(200)
    domains = Array(exclusion_list["domains"]).first(200)
    lines = names.map { |name| "- #{name}" } + domains.map { |domain| "- #{domain}" }
    lines.presence&.join("\n") || "- none provided"
  end

  def parse_companies_json(content)
    text = content.to_s.strip
    json_text = text[/\{.*\}/m] || text
    JSON.parse(json_text)
  rescue JSON::ParserError
    { "companies" => [] }
  end

  def build_company_payload(company, search_urls)
    name = company["name"].to_s.strip
    website = clean_url(company["website"])
    return if name.blank? || website.blank?

    # Evidence-gate the founding year: only keep it when the model returned a source
    # URL it actually saw in search. An uncited year is effectively a guess, so we drop
    # it and let the sourced backfill fill it later (cite-only, never fabricate).
    founded_year_source = cited_source_url(company["founded_year_source"], search_urls)
    founded_date = founded_year_source.present? ? company["founded_date"].to_s.strip.presence : nil

    payload = {
      "name" => name,
      "website" => website,
      "location" => company["location"].to_s.strip.presence,
      "founded_date" => founded_date,
      "description" => company["description"].to_s.squish.presence,
      "why_discovered" => company["why_discovered"].to_s.squish.presence,
      "discovery_type" => discovery_type,
      "discovery_query" => search_query,
      "website_verified" => verified_website?(website, search_urls),
      "category_name" => company["category"].to_s.strip.presence,
      "secondary_category_name" => company["secondary_category"].to_s.strip.presence,
      "business_model_names" => clean_name_list(company["business_models"]),
      "target_client_names" => clean_name_list(company["target_clients"]),
      "tag_names" => clean_name_list(company["tags"]),
      "founded_year_source" => founded_year_source
    }
    payload.merge!(funding_hint_payload(company)) if discovery_type == "funding_year"
    payload.compact
  end

  def clean_name_list(value)
    Array(value).map { |name| name.to_s.strip }.reject(&:blank?).uniq
  end

  # Keep a founding-year source only if it is one of the URLs the model actually
  # saw in search (anti-hallucination guard, mirroring website verification).
  def cited_source_url(url, search_urls)
    cleaned = clean_url(url)
    return nil if cleaned.blank?

    domain = Company.canonical_domain_for(cleaned)
    return nil if domain.blank?

    cited = search_urls.any? do |candidate|
      candidate_domain = Company.canonical_domain_for(candidate)
      candidate_domain.present? && (candidate_domain == domain || candidate_domain.end_with?(".#{domain}") || domain.end_with?(".#{candidate_domain}"))
    end
    cited ? cleaned : nil
  end

  def verified_website?(website, search_urls)
    domain = Company.canonical_domain_for(website)
    return false if domain.blank?

    search_urls.any? do |url|
      cited_domain = Company.canonical_domain_for(url)
      next false if cited_domain.blank?

      cited_domain == domain || cited_domain.end_with?(".#{domain}") || domain.end_with?(".#{cited_domain}")
    end
  end

  def funding_hint_payload(company)
    {
      "funding_round_year" => company["funding_round_year"].to_s.strip.presence,
      "funding_round_type" => company["funding_round_type"].to_s.strip.presence,
      "funding_amount_hint" => company["funding_amount_hint"].to_s.squish.presence
    }.compact
  end

  def clean_url(url)
    value = url.to_s.strip
    return nil if value.blank?

    value.match?(%r{\Ahttps?://}i) ? value : "https://#{value}"
  end
end
