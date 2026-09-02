# The model half of DescriptionVerificationService: judges a proposed description
# against page text that has already been retrieved.
#
# It is given the pages, not the web. There is no search tool here on purpose — the
# service enforces that citations come from pages it opened itself, so handing the model
# a search tool would only let it produce URLs the service then throws away.
class DescriptionVerificationAgent < RubyLLM::Agent
  model "gpt-5.5"
  temperature 0.1

  DEFAULT_TIMEOUT_SECONDS = 90

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company_name:, company_url:, proposed_description:, retrieved_pages:)
    @company_name = company_name
    @company_url = company_url
    @proposed_description = proposed_description
    @retrieved_pages = retrieved_pages
  end

  def call
    chat = self.class.chat(model: verification_model, provider: :openai, assume_model_exists: true)
    response = Timeout.timeout(timeout_seconds) { chat.ask(prompt) }
    parse_json(response.content)
  end

  private

  attr_reader :company_name, :company_url, :proposed_description, :retrieved_pages

  def verification_model
    ENV.fetch("RUBYLLM_VERIFICATION_MODEL", ENV.fetch("RUBYLLM_HARD_MODEL", "gpt-5.5"))
  end

  def timeout_seconds
    ENV.fetch("DESCRIPTION_VERIFICATION_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS.to_s).to_i
  end

  def prompt
    {
      record: { company_name: company_name, company_url: company_url, proposed_description: proposed_description },
      retrieved_pages: retrieved_pages.map do |page|
        { url: page["final_url"].presence || page["url"], title: page["title"], text: page["text"] }
      end,
      instruction: instruction,
      output_shape: output_shape
    }.to_json
  end

  def instruction
    <<~TEXT.squish
      You are verifying a Stanford TechIndex directory entry. Work ONLY from retrieved_pages:
      it is the full text of pages fetched from the company's own site. You have no other
      sources. The proposed_description is the thing under review and is never evidence for
      itself.

      Resolve identity FIRST, before judging any claim. Determine the legal entity or company
      name, the legal-technology product or platform name, and the relationship between them.
      They are frequently different: a company may operate a differently-named product, and a
      company may have several products. Do not treat a product, platform, brand or service
      name as the company name, and do not infer either from the other or from the domain
      alone — a shared domain does not make the two names interchangeable. Use About, Terms,
      Privacy, legal notices, imprint, footer and product pages to establish it. If you cannot
      establish the relationship from the retrieved pages, return MANUAL_REVIEW and say so;
      do not guess.

      Then judge every material claim in the description separately. Verifying one capability
      is not evidence for any other. A capability counts as present only if the pages show it
      is currently available — planned, beta, experimental or discontinued functionality must
      not be described as active. Remove promotional language, superlatives, testimonials,
      performance promises and subjective claims. Be precise about what the technology does
      and keep the distinctions between preparing, reviewing, generating, submitting, filing,
      representing, advising and automating. Never imply the company performs regulated or
      professional services unless a page explicitly establishes that it does, and name a
      material limitation when leaving it out would mislead. Check geographic claims against
      an explicit statement on a page. Do not add facts to make the description fuller.

      Decisions: APPROVE only when company, product, their relationship and every material
      claim are verified and no change is needed. REVISE when identity is established and the
      company belongs in the index but the wording is inaccurate, unsupported, promotional,
      outdated, ambiguous or too broad — then supply corrected_description, preserving what
      was verified and changing only what must change. MANUAL_REVIEW when evidence is
      insufficient, pages conflict, the company/product relationship is unresolved, product
      status is unclear, or a regulated-service claim cannot be characterised confidently.
      REJECT only when the company does not belong in a legal-technology index or no
      verifiable product exists.

      Every URL in sources must be one of the retrieved_pages URLs, and only those you
      actually relied on. Cite the specific page that carried the evidence, not the homepage.
      Return a single JSON object matching output_shape and no prose.
    TEXT
  end

  def output_shape
    {
      "decision" => "APPROVE | REVISE | MANUAL_REVIEW | REJECT",
      "verified_company" => "legal entity or company name, or null",
      "verified_product" => "legal technology product or platform name, or null",
      "company_product_relationship" => "one sentence on the verified relationship, or null",
      "accuracy_assessment" => "concise explanation supporting the decision",
      "verified_claims" => ["material claims confirmed by the retrieved pages"],
      "issues_found" => ["specific inaccurate, unsupported, outdated, promotional, ambiguous, overly broad or misattributed statements"],
      "corrected_description" => "publication-ready description, required for REVISE, else null",
      "sources" => ["URLs from retrieved_pages that you actually relied on"],
      "confidence" => "HIGH | MEDIUM | LOW"
    }
  end

  def parse_json(content)
    return content if content.is_a?(Hash)

    text = content.to_s.strip
    JSON.parse(text[/\{.*\}/m] || text)
  rescue JSON::ParserError
    {}
  end
end
