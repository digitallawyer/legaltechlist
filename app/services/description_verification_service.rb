# Verifies a proposed description against pages actually retrieved from the company's
# own site, and resolves who the company is before judging what the description says.
#
# Two things make this different from the description critic it supersedes on this path.
#
# First, entity identity comes before accuracy. A product name is not a company name:
# Aidvocates Inc. operates LEGAION, and a review that treats those as interchangeable
# has not verified anything, however confident its prose. When the relationship cannot
# be established from the retrieved pages, the verdict is MANUAL_REVIEW — never APPROVE.
#
# Second, the source safeguards are enforced here rather than asked for in the prompt.
# The model can only cite pages this service retrieved; any URL it returns that is not
# in that set is dropped, and if that leaves a claim unsupported the confidence falls
# and the verdict downgrades. A model cannot talk its way past a set intersection.
class DescriptionVerificationService
  APPROVE = "APPROVE".freeze
  REVISE = "REVISE".freeze
  MANUAL_REVIEW = "MANUAL_REVIEW".freeze
  REJECT = "REJECT".freeze
  # Verification that did not happen is not a verdict. Recorded so a reviewer can see
  # it was skipped and why, but it does not hold publication: the evidence gate already
  # blocks a record nothing was retrieved for, and blocking twice for one absence only
  # obscures which condition the reviewer has to satisfy.
  SKIPPED = "SKIPPED".freeze
  DECISIONS = [APPROVE, REVISE, MANUAL_REVIEW, REJECT].freeze

  BLOCKING_DECISIONS = [MANUAL_REVIEW, REJECT].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company_name:, company_url:, proposed_description:, linkedin_url: nil, crunchbase_url: nil, site_evidence: nil)
    @company_name = company_name.to_s.strip
    @company_url = company_url.to_s.strip
    @proposed_description = proposed_description.to_s.strip
    @linkedin_url = linkedin_url
    @crunchbase_url = crunchbase_url
    @provided_evidence = site_evidence
  end

  def call
    return insufficient_evidence_result if retrieved_pages.empty?
    return disabled_result unless llm_enabled?

    parsed = DescriptionVerificationAgent.call(
      company_name: company_name,
      company_url: company_url,
      proposed_description: proposed_description,
      retrieved_pages: retrieved_pages
    )
    return disabled_result if parsed.blank?

    validate(parsed)
  rescue StandardError => e
    Rails.logger.debug("[DescriptionVerificationService] failed for #{company_name}: #{e.class}: #{e.message}")
    skipped("The verification step could not run (#{e.class.name}), so this description has not been checked. This is a fault on our side, not a finding about the record.")
  end

  # What the publish gate needs to know, without it having to understand the payload.
  def self.blocking?(result)
    result.present? && BLOCKING_DECISIONS.include?(result["decision"])
  end

  private

  attr_reader :company_name, :company_url, :proposed_description, :linkedin_url, :crunchbase_url

  def site_evidence
    @site_evidence ||= @provided_evidence || SiteEvidenceFetcherService.call(
      main_url: company_url, linkedin_url: linkedin_url, crunchbase_url: crunchbase_url
    )
  end

  # The only pages that may be cited. A page we could not open is not evidence, and a
  # search snippet was never a page at all.
  def retrieved_pages
    @retrieved_pages ||= Array(site_evidence["pages"]).select { |page| page["status"] == "fetched" && page["text"].to_s.strip.present? }
  end

  def retrieved_urls
    @retrieved_urls ||= retrieved_pages.map { |page| page["final_url"].presence || page["url"] }.compact
  end

  def llm_enabled?
    ENV["OPENAI_API_KEY"].present? &&
      ENV.fetch("DESCRIPTION_VERIFICATION_USE_LLM", ENV.fetch("DESCRIPTION_DRAFTS_USE_LLM", "true")) == "true"
  end

  # Everything the model returned, filtered down to what it is actually entitled to
  # claim, then downgraded where the filtering left it short.
  def validate(parsed)
    decision = parsed["decision"].to_s.upcase
    decision = MANUAL_REVIEW unless DECISIONS.include?(decision)

    kept, dropped = partition_sources(parsed["sources"])
    entity_resolved = entity_resolved?(parsed)

    notes = []
    notes << "Dropped #{dropped.size} cited source#{'s' unless dropped.size == 1} that were not among the pages actually retrieved." if dropped.any?

    # An approval has to rest on a resolved entity and on at least one real page.
    if decision == APPROVE && !entity_resolved
      decision = MANUAL_REVIEW
      notes << "The company and product could not both be identified, so this cannot be approved on the description alone."
    end
    if decision == APPROVE && kept.empty?
      decision = MANUAL_REVIEW
      notes << "No verifiable source page supports the description."
    end

    confidence = parsed["confidence"].to_s.upcase.presence || "LOW"
    confidence = "LOW" if dropped.any? || kept.empty?

    {
      "decision" => decision,
      "verified_company" => parsed["verified_company"].to_s.strip.presence,
      "verified_product" => parsed["verified_product"].to_s.strip.presence,
      "company_product_relationship" => parsed["company_product_relationship"].to_s.strip.presence,
      "accuracy_assessment" => parsed["accuracy_assessment"].to_s.strip.presence,
      "verified_claims" => clean_list(parsed["verified_claims"]),
      "issues_found" => clean_list(parsed["issues_found"]),
      "corrected_description" => corrected_description_for(decision, parsed),
      "sources" => kept,
      "rejected_sources" => dropped,
      "confidence" => confidence,
      "validation_notes" => notes,
      "pages_retrieved" => retrieved_urls,
      "entity_resolved" => entity_resolved,
      "mode" => "llm_verified",
      "generated_at" => Time.current.utc.iso8601
    }
  end

  # Sources are an intersection, not a claim: only pages this service opened count.
  def partition_sources(sources)
    cited = clean_list(sources)
    kept, dropped = cited.partition { |url| retrieved_urls.any? { |page| same_page?(url, page) } }
    [kept.uniq, dropped.uniq]
  end

  def same_page?(a, b)
    normalize_url(a) == normalize_url(b)
  end

  def normalize_url(url)
    parsed = URI.parse(url.to_s.strip.downcase)
    host = parsed.host.to_s.delete_prefix("www.")
    "#{host}#{parsed.path.to_s.delete_suffix('/')}"
  rescue URI::InvalidURIError
    url.to_s.strip.downcase
  end

  # Both halves of the identity, and a stated relationship between them.
  def entity_resolved?(parsed)
    parsed["verified_company"].to_s.strip.present? &&
      parsed["verified_product"].to_s.strip.present? &&
      parsed["company_product_relationship"].to_s.strip.present?
  end

  # A correction is only meaningful on REVISE, and only if it clears the same
  # deterministic gate every other published description has to clear.
  def corrected_description_for(decision, parsed)
    return nil unless decision == REVISE

    corrected = parsed["corrected_description"].to_s.strip
    return nil if corrected.blank?

    verdict = CompanyProposalEnrichmentService.description_critic_for(corrected)
    verdict["verdict"] == "pass" ? corrected : nil
  end

  def clean_list(value)
    Array(value).map { |item| item.to_s.strip }.reject { |item| item.blank? || item.casecmp?("none") }
  end

  def insufficient_evidence_result
    skipped(
      "None of the company's own pages could be retrieved, so neither the entity nor the description could be verified.",
      notes: Array(site_evidence["pages"]).reject { |page| page["status"] == "fetched" }
                                         .map { |page| "#{page['label']}: #{page['status']}#{" (#{page['reason']})" if page['reason'].present?}" }
    )
  end

  def disabled_result
    skipped("Automated verification is unavailable, so this description has not been checked against the company's pages.")
  end

  def skipped(assessment, notes: [])
    stub_result(SKIPPED, assessment, notes: notes)
  end

  def manual_review(assessment, notes: [])
    stub_result(MANUAL_REVIEW, assessment, notes: notes)
  end

  def stub_result(decision, assessment, notes: [])
    {
      "decision" => decision,
      "verified_company" => nil,
      "verified_product" => nil,
      "company_product_relationship" => nil,
      "accuracy_assessment" => assessment,
      "verified_claims" => [],
      "issues_found" => [],
      "corrected_description" => nil,
      "sources" => [],
      "rejected_sources" => [],
      "confidence" => "LOW",
      "validation_notes" => notes,
      "pages_retrieved" => retrieved_urls,
      "entity_resolved" => false,
      "mode" => decision == SKIPPED ? "skipped" : "unverified",
      "generated_at" => Time.current.utc.iso8601
    }
  end
end
