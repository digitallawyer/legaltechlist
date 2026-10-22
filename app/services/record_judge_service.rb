require "digest"

# The one place an existing company is judged from evidence.
#
#   1. Evidence: the company's own pages, fetched by the server (following script redirects,
#      retrying a refusal as a browser) and kept as snapshots. A fresh, unchanged snapshot is
#      reused, so nobody fetches or reads the same page twice.
#   2. Judgement: RecordJudgeAgent, toolless, sees only those pages. When there is nothing to
#      read (no URL, DNS failure, blocked, empty) no model is called and nothing is invented:
#      the answer is needs_work with the reason.
#   3. Grounding: the entry text must come with quotes that really occur on the pages, and
#      must pass the publication gate. Failing either turns a "list" into "needs_work".
#   4. Ledger: every judgement is a review event tied to the evidence hash, so a repeat of the
#      same evidence returns the earlier judgement instead of paying for a second one.
#
# It never writes to the company. Applying a result is a separate, audited step.
class RecordJudgeService
  PAGE_LIMIT = 2 # the front page and /about
  REUSE_EVENT_FOR = 14.days

  # An earlier judgement is only reusable when the same instructions and rules would give it
  # again: the prompt, the schema and this file's logic are all part of the cache key.
  def self.version
    @version ||= Digest::SHA256.hexdigest([
      File.read(Rails.root.join("app/prompts/record_judge_agent/instructions.txt.erb")),
      RecordJudgeSchema::SCHEMA_VERSION,
      File.read(__FILE__),
      CompanyProposalEnrichmentService::HEDGE_PATTERN.source, CompanyProposalEnrichmentService::META_PATTERN.source
    ].join("\0")).first(12)
  end

  def self.call(company:, refresh: false, model: nil, record: true)
    new(company: company, refresh: refresh, model: model, record: record).call
  end

  def initialize(company:, refresh:, model:, record:)
    @company = company
    @refresh = refresh
    @model = model.presence || RecordJudgeAgent.default_model
    @record = record
  end

  def call
    snapshots = evidence
    readable = snapshots.select { |snap| snap.status == "fetched" && (snap.text.present? || snap.title.present?) }
    hash = evidence_hash(readable)
    # A page that refused us after redirecting somewhere else still tells where it ended up.
    unread_redirects = readable.empty? ? snapshots.select { |snap| snap.kind == "website" && snap.status != "fetched" && redirected_off_site?(snap) } : []

    unless refresh
      cached = reusable_event(hash)
      return result_from_event(cached, snapshots).merge("reused" => true) if cached
    end

    result = if readable.any?
      judged(readable)
    elsif unread_redirects.any?
      judged(unread_redirects, hash_source: unread_redirects)
    else
      unreadable_result(snapshots)
    end

    result["evidence"] = evidence_summary(snapshots)
    result["evidence_hash"] = hash
    event = record_event(result, hash) if record
    result["event_id"] = event&.id
    result
  end

  private

  attr_reader :company, :refresh, :model, :record

  def evidence
    fresh = company.evidence_snapshots.fresh.order(fetched_at: :desc).to_a.uniq(&:kind).sort_by(&:fetched_at)
    return fresh if !refresh && fresh.any? { |snap| snap.kind == "website" }

    fetch_and_store
  end

  def fetch_and_store
    return [] if company.main_url.blank?

    payload = SiteEvidenceFetcherService.new(main_url: company.main_url, entity_paths: %w[/about]).call
    Array(payload["pages"]).filter_map do |page|
      next unless %w[website website_about].include?(page["label"])
      next if page["status"] == "skipped"

      text = page["text"].to_s
      company.evidence_snapshots.create!(
        kind: page["label"] == "website" ? "website" : "about",
        url: page["url"], final_url: page["final_url"], status: page["status"], reason: page["reason"],
        http_status: page["http_status"], renders_text: page.fetch("renders_text", text.present?),
        title: page["title"], meta_description: page["meta_description"], text: text.presence,
        content_hash: text.present? || page["title"].present? ? Digest::SHA256.hexdigest("#{page['title']}|#{page['meta_description']}|#{text}") : nil,
        fetched_at: Time.current
      )
    end
  end

  def judged(readable, hash_source: nil)
    pages = readable.map do |snap|
      { url: snap.url, final_url: snap.final_url, fetched: snap.status == "fetched", renders_text: snap.renders_text, title: snap.title, meta_description: snap.meta_description, text: snap.text }
    end
    raw = RecordJudgeAgent.call(company: company, pages: pages, model: model)
    return { "decision" => "needs_work", "scope" => "unreadable", "description" => "", "reason" => "The review model did not answer; nothing was concluded.", "confidence" => 0.0, "model" => model, "grounded" => false } unless raw

    result = ground(raw, readable)
    # One chance to fix a description the gate refused, with the reasons in front of the model.
    if result["downgraded_from"] == "list" && result["description_issues"].present?
      again = RecordJudgeAgent.call(company: company, pages: pages, model: model,
                                    feedback: "Your description was refused: #{result['description_issues'].join(' ')} Write it again from the pages, stating only what the company does, or answer needs_work.")
      if again
        retried = ground(again, readable)
        result = retried.merge("retried" => true) if retried["decision"] != "needs_work" || retried["description_issues"].blank?
      end
    end
    result
  end

  def redirected_off_site?(snap)
    return false if snap.final_url.blank?

    URI.parse(snap.final_url).host.to_s.sub(/\Awww\./, "") != URI.parse(snap.url).host.to_s.sub(/\Awww\./, "")
  rescue URI::InvalidURIError
    false
  end

  # A listing needs text that is on the pages and clears the gate; otherwise it is not a listing.
  def ground(raw, readable)
    result = raw.slice("scope", "decision", "description", "support_quotes", "successor_note", "reason", "confidence", "model", "usage")
    result["decision"] = "needs_work" unless %w[list close needs_work].include?(result["decision"])
    corpus = normalise(readable.flat_map { |snap| [snap.readable, snap.final_url] }.join(" "))
    quotes = Array(result["support_quotes"]).map(&:to_s).reject(&:blank?)
    verified = quotes.select { |quote| corpus.include?(normalise(quote)) }
    result["quotes_verified"] = "#{verified.size}/#{quotes.size}"
    issues = result["decision"] == "list" ? CompanyProposalEnrichmentService.description_issues(result["description"], company_name: company.name) : []
    result["description_issues"] = issues

    if result["decision"] == "list"
      problem = if result["description"].to_s.strip.blank? then "no description"
      elsif verified.empty? then "no quote from the pages supports the description"
      elsif issues.any? then "the description fails the publication gate (#{issues.first})"
      end
      if problem
        result["downgraded_from"] = "list"
        result["decision"] = "needs_work"
        result["reason"] = "#{result['reason']} Downgraded: #{problem}."
      end
    end
    # Closing removes a company for good, so it needs the page's own words, not a conclusion.
    if result["decision"] == "close" && verified.empty?
      result["downgraded_from"] = "close"
      result["decision"] = "needs_work"
      result["reason"] = "#{result['reason']} Downgraded: no quote from the pages shows why."
    end
    result["description"] = "" unless result["decision"] == "list"
    result["grounded"] = %w[list close].include?(result["decision"]) ? verified.any? : true
    result
  end

  def unreadable_result(snapshots)
    website = snapshots.find { |snap| snap.kind == "website" }
    why = if company.main_url.blank? then "the record has no website"
    elsif website.nil? then "no page could be fetched"
    else "the website could not be read (#{website.status}#{": #{website.reason}" if website.reason.present?})"
    end
    { "decision" => "needs_work", "scope" => "unreadable", "description" => "", "support_quotes" => [], "reason" => "No model was called: #{why}.", "confidence" => 0.0, "model" => nil, "grounded" => true }
  end

  def evidence_summary(snapshots)
    snapshots.map do |snap|
      { "kind" => snap.kind, "status" => snap.status, "reason" => snap.reason, "final_url" => snap.final_url || snap.url, "renders_text" => snap.renders_text, "title" => snap.title, "fetched_at" => snap.fetched_at.utc.iso8601 }
    end
  end

  def evidence_hash(readable)
    return nil if readable.empty?

    Digest::SHA256.hexdigest(readable.map { |snap| "#{snap.kind}:#{snap.content_hash}" }.join("|"))
  end

  def reusable_event(hash)
    return nil if hash.blank?

    company.review_events.judgements.where(evidence_hash: hash, model: model).where("details ->> 'judge_version' = ?", self.class.version).where("occurred_at > ?", REUSE_EVENT_FOR.ago).order(occurred_at: :desc).first
  end

  def result_from_event(event, snapshots)
    event.details.merge("evidence" => evidence_summary(snapshots), "evidence_hash" => event.evidence_hash, "event_id" => event.id)
  end

  def record_event(result, hash)
    company.review_events.create!(
      kind: "judge", actor: Mcp::Current.operator_email || "system", model: model, decision: result["decision"],
      scope: result["scope"], confidence: result["confidence"].to_f, evidence_hash: hash, occurred_at: Time.current,
      details: result.except("evidence", "evidence_hash", "event_id").merge("judge_version" => self.class.version)
    )
  end

  def normalise(text)
    text.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, " ").squish
  end
end
