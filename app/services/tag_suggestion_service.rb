require "timeout"

class TagSuggestionService
  HIGH_CONFIDENCE = 0.65
  MAX_TAGS = 5

  def self.call(company:, dry_run: true, min_confidence: nil, max_tags: MAX_TAGS)
    new(company: company, dry_run: dry_run, min_confidence: min_confidence, max_tags: max_tags).call
  end

  def initialize(company:, dry_run: true, min_confidence: nil, max_tags: MAX_TAGS)
    @company = company
    @dry_run = dry_run
    @min_confidence = min_confidence || default_min_confidence
    @max_tags = max_tags
  end

  def call
    return skip("already_tagged") if company.tags.any?
    return skip("human_reviewed") if company.human_reviewed_at.present? && !allow_human_reviewed_tags?

    keyword_result = CompanyTagBackfillService.call(company: company, dry_run: dry_run, max_tags: max_tags)
    return keyword_result if keyword_result["action"].in?(%w[tagged would_tag])

    return skip("llm_disabled") unless llm_enabled?

    suggestion = llm_suggestion
    names = Array(suggestion["tag_names"]).map { |name| TagNormalizationService.canonical_name(name) }.compact.uniq
    names = TagTaxonomyService.filter_assignable(names).first(max_tags)
    confidence = suggestion["confidence"].to_f
    return skip("no_suggestion", names, confidence, suggestion["mode"]) if names.empty?
    return skip("low_confidence", names, confidence, suggestion["mode"]) if confidence < min_confidence

    unless dry_run
      company.tags = names.filter_map { |name| TagNormalizationService.find_or_create_canonical(name) }
    end

    {
      "company_id" => company.id,
      "company_name" => company.name,
      "suggested_tags" => names,
      "confidence" => confidence,
      "mode" => suggestion["mode"],
      "action" => dry_run ? "would_tag" : "tagged"
    }
  end

  private

  attr_reader :company, :dry_run, :min_confidence, :max_tags

  def default_min_confidence
    return AUTO_CONFIDENCE if ENV.fetch("AUTO_HYGIENE", "false") == "true"

    ENV.fetch("MIN_CONFIDENCE", HIGH_CONFIDENCE.to_s).to_f
  end

  AUTO_CONFIDENCE = 0.55

  def llm_suggestion
    TagSuggestionAgent.call(company: company, max_tags: max_tags)
  end

  def llm_enabled?
    defined?(RubyLLM) &&
      ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("TAG_SUGGESTION_USE_LLM", ENV.fetch("PROPOSAL_TAXONOMY_USE_LLM", Rails.env.production? ? "true" : "false")) == "true"
  end

  def effective_description
    text = company.description.to_s.strip
    return nil if text.blank? || text == "No description yet"

    text
  end

  def allow_human_reviewed_tags?
    ENV.fetch("ALLOW_HUMAN_REVIEWED_TAGS", "false") == "true"
  end

  def skip(reason, suggested_tags = nil, confidence = nil, mode = nil)
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "suggested_tags" => suggested_tags,
      "confidence" => confidence,
      "mode" => mode,
      "action" => "skipped_#{reason}"
    }
  end
end
