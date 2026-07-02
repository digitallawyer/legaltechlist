# TechIndex Server-Side Founded-Date Hardening — Implementation Specs

## Context

- **Server**: TechIndex Rails app, v1.6.0. Repo root: this working tree.
- **Cite-only rule** (existing invariant): `founded_date` is never guessed. `CompanyProposalEnrichmentService.sourced_year` (`app/services/company_proposal_enrichment_service.rb:23-33`) accepts a year only when the citing source host is present in the evidence we actually gathered. `UpdateCompanyFieldTool` (`app/mcp/tools/update_company_field_tool.rb:41-45`) requires a `source_url` whenever `founded_date` is set. `founded_date` is column type `string` (see `db/schema.rb:84`) and validated as a 4-digit year, `allow_blank: true` (`app/models/company.rb:44`). This is intentional — do not change.
- **Motivating run**: a client-driven backfill run today processed 50 candidates and filled **6/50** years; roughly **40 skips** were egress-blocked sandbox 403s (the client couldn't reach LinkedIn/Crunchbase/registry hosts). Moving the backfill server-side (which does have that egress via `CompanyProposalResearchService` / OpenAI Responses web search) is the point of Spec B.
- **Scope of visibility conventions**: the existing "missing_" scopes (`missing_main_url`, `weak_description`) are defined on `Company` without a `visible: true` clause and are consumed both by `AdminDashboardMetrics.compute` and by `get_stats` unfiltered. Match that — the new `missing_founded_date` scope is not visibility-scoped either.

Style you are matching, verbatim: existing scopes at `app/models/company.rb:50-72`; metric shape at `app/services/admin_dashboard_metrics.rb:28-39`; tool exposure at `app/mcp/tools/get_stats_tool.rb:15-25`; MCP input-schema style at `app/mcp/tools/search_companies_tool.rb`; base helpers (`json_response`, `not_found`, `error_response`, `audit!`, `find_company`, `company_summary`) at `app/mcp/tools/base_tool.rb`; rake dry-run + counters idiom at `lib/tasks/data_quality.rake:80-108`; ActiveJob pattern at `app/jobs/enrich_proposal_job.rb`.

Cross-cutting non-goals (apply to all specs): do NOT change the "founded_date is non-blocking for publish" behavior in `CompanyProposalQualityService` (see the assertion in `test/mcp/curator_tools_test.rb:240-256`). Do NOT alter discovery-time capture behavior in `CompanyDiscoverySearchService#cited_source_url` — that helper is the *pattern to reuse*, not to modify. No new env vars or Rails config; a small registry-host constant is fine.

---

## Spec A — Missing-founded-date visibility (scope + metric + filter)

### Goal
Make "companies with no founded_date" a first-class, queryable quality signal: model scope, admin metric, MCP stats field, and an MCP search filter.

### Files to change
- `app/models/company.rb` (add scope)
- `app/services/admin_dashboard_metrics.rb` (add count to `company_summary_counts`)
- `app/mcp/tools/get_stats_tool.rb` (expose in JSON payload)
- `app/mcp/tools/search_companies_tool.rb` (new boolean filter)
- `test/models/company_test.rb` (new scope test — create the file if it does not already exist, using standard `ActiveSupport::TestCase` style)
- `test/mcp/curator_tools_test.rb` (new filter test)

### What to add/change

**`app/models/company.rb`** — insert alongside the other `missing_` scopes at line ~51, matching their one-line style. `founded_date` is a `string` (`db/schema.rb:84`), so match `missing_main_url`'s NULL-or-empty predicate:

```ruby
scope :missing_founded_date, -> { where(founded_date: [nil, ""]) }
```

**`app/services/admin_dashboard_metrics.rb`** — in the `company_summary_counts` hash literal (line 28-39), add a `missing_founded_date` entry mirroring `missing_url`:

```ruby
company_summary_counts: {
  total: Company.count,
  # ...
  missing_url: Company.missing_main_url.count,
  missing_founded_date: Company.missing_founded_date.count,
  weak_description: Company.weak_description.count,
  # ...
}
```

**`app/mcp/tools/get_stats_tool.rb`** — inside the `"companies"` sub-hash of the `json_response` call (line 15-26), add one line mirroring `"missing_url"`:

```ruby
"missing_url" => summary[:missing_url],
"missing_founded_date" => summary[:missing_founded_date],
"weak_description" => summary[:weak_description],
```

**`app/mcp/tools/search_companies_tool.rb`** — add the input-schema entry and a kwarg + scope-composition line, AND-composed with existing `needs_review`:

```ruby
input_schema(
  properties: {
    query: { type: "string", description: "Free-text query matched against name, description, and location." },
    limit: { type: "integer", description: "Max results (1-25, default 10)." },
    needs_review: { type: "boolean", description: "Only return companies whose quality_status is needs_review." },
    missing_founded_date: { type: "boolean", description: "Only return companies with no founded_date set." }
  },
  required: []
)

def self.call(server_context:, query: nil, limit: 10, needs_review: false, missing_founded_date: false)
  capped = [[limit.to_i, 1].max, 25].min
  scope = Company.publicly_visible.includes(:category, :secondary_category)
  scope = scope.needs_review if needs_review
  scope = scope.missing_founded_date if missing_founded_date
  scope = scope.text_search(query) if query.present?
  # ...
end
```

### Acceptance criteria
- `Company.missing_founded_date` returns exactly the companies whose `founded_date` is `nil` OR `""`. Model test asserts both a matching and a non-matching fixture.
- `AdminDashboardMetrics.load[:company_summary_counts][:missing_founded_date]` returns an integer equal to `Company.missing_founded_date.count`.
- `get_stats` JSON contains `data["companies"]["missing_founded_date"]` (integer), asserted in `test/mcp/curator_tools_test.rb` alongside the existing `"get_stats returns directory and backlog counts"` test (extend or add a sibling test).
- `search_companies(missing_founded_date: true)` returns only companies whose `founded_date` is blank; combined with `needs_review: true` returns the intersection. New test in `test/mcp/curator_tools_test.rb` following the existing `call(Mcp::Tools::SearchCompaniesTool, ...)` idiom.
- Full existing suite still passes.

### Non-goals
- Do not add a visibility filter to the scope (`missing_main_url` doesn't have one either).
- Do not alter publish-blocking behavior.

---

## Spec B — Server-side founded_date backfill (rake + ActiveJob + MCP wrapper)

### Goal
Backfill blank `founded_date` values from the server (which has real web egress), reusing the *exact* cite-only guard (`CompanyProposalEnrichmentService.sourced_year`) and the *exact* validated writer path (`UpdateCompanyFieldTool`'s `plausible_year?` + `valid_http_url?` + `company.save!`), and record provenance so any backfilled year is auditable.

### Files to change / add
- **NEW** `app/services/company_founded_date_backfill_service.rb`
- **NEW** `app/jobs/backfill_founded_date_job.rb`
- **NEW** `app/mcp/tools/backfill_founded_dates_tool.rb`
- `app/mcp/tools.rb` — register the new tool
- `lib/tasks/data_quality.rake` — new task `data_quality:backfill_founded_dates`
- `app/models/company.rb` — extract a shared `founded_date_from_source!` helper (see below)
- `app/mcp/tools/update_company_field_tool.rb` — call the shared helper (no logic change from a curator's POV)
- **NEW** `test/services/company_founded_date_backfill_service_test.rb`
- `test/mcp/curator_tools_test.rb` — new test for `BackfillFoundedDatesTool`

### What to add/change

**Shared validated writer** — move the founded_date validation currently inline in `UpdateCompanyFieldTool.call` (`app/mcp/tools/update_company_field_tool.rb:41-49`) into a Company instance method so both the tool and the backfill service call the same code (no copy-paste). Keep `plausible_year?` / `valid_http_url?` as class methods on the tool (that's where they live today).

In `app/models/company.rb`, add:

```ruby
EARLIEST_PLAUSIBLE_FOUNDING_YEAR = 1970

def founded_date_from_source!(year:, source_url:)
  raise ArgumentError, "founded_date must be a 4-digit year 1970-#{Date.current.year}" unless plausible_founding_year?(year)
  raise ArgumentError, "source_url required (cite-only)" unless self.class.valid_http_url?(source_url)

  self.founded_date = year.to_s.strip
  save!
end

def self.valid_http_url?(value)
  uri = URI.parse(value.to_s.strip)
  uri.is_a?(URI::HTTP) && uri.host.present?
rescue URI::InvalidURIError
  false
end

def plausible_founding_year?(value)
  value.to_s.strip.match?(/\A(?:19|20)\d{2}\z/) &&
    (EARLIEST_PLAUSIBLE_FOUNDING_YEAR..Date.current.year).cover?(value.to_s.strip.to_i)
end
```

Then `UpdateCompanyFieldTool.call` (`app/mcp/tools/update_company_field_tool.rb`), when applying `founded_date`, calls `company.founded_date_from_source!(year: ..., source_url: source_url)` instead of the inline setter. Other fields continue through the current `public_send("#{field}=", value)` + `save!` path. Preserve the existing `error_response("result" => "blocked", "retryable" => false, "error" => …)` shape for `ArgumentError` and the `plausible_year?` / `valid_http_url?` class methods (the tool's own guard runs first so the JSON error text is unchanged).

**`app/services/company_founded_date_backfill_service.rb`** — new. Reuses `CompanyProposalResearchService` and `CompanyProposalEnrichmentService.sourced_year` verbatim. Does NOT duplicate the sourced_year logic.

```ruby
require "timeout"

class CompanyFoundedDateBackfillService
  RESULT_KEYS = %i[filled skipped_no_source skipped_no_year skipped_present error].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company:, admin_user: nil)
    @company = company
    @admin_user = admin_user
  end

  # Returns a hash: { result:, company_id:, year:, source_url:, source_tier:, reason: }
  def call
    return { "result" => "skipped_present", "company_id" => company.id } if company.founded_date.present?

    research = fetch_research
    candidates = extract_candidates(research)
    chosen = choose_candidate(candidates)
    return { "result" => "skipped_no_source", "company_id" => company.id, "reason" => "no cited candidate year in gathered evidence" } if chosen.nil?

    company.founded_date_from_source!(year: chosen[:year], source_url: chosen[:source_url])
    record_provenance!(chosen)
    audit!(chosen)

    { "result" => "filled", "company_id" => company.id, "year" => chosen[:year], "source_url" => chosen[:source_url], "source_tier" => chosen[:tier] }
  rescue ArgumentError => e
    { "result" => "skipped_no_year", "company_id" => company.id, "reason" => e.message }
  rescue StandardError => e
    Rails.logger.debug("[CompanyFoundedDateBackfillService] company_id=#{company.id} #{e.class}: #{e.message}")
    { "result" => "error", "company_id" => company.id, "reason" => "#{e.class}: #{e.message}" }
  end

  private

  attr_reader :company, :admin_user

  def fetch_research
    # Reuse the existing research service. It accepts :proposal today; construct a lightweight
    # shim proposal-like object OR (preferred) add a keyword-args entry point that takes name+url.
    # See "Research entry point" note below.
    CompanyProposalResearchService.call(company: company)
  end

  # Pull {year, source_url} pairs from research_payload["results"] then filter through the SAME
  # cite-only guard used by proposal enrichment.
  def extract_candidates(research_payload)
    allowed_hosts = evidence_hosts(research_payload)
    Array(research_payload["candidates"]).filter_map do |cand|
      year = CompanyProposalEnrichmentService.sourced_year(
        year: cand["year"], source: cand["source_url"], allowed_hosts: allowed_hosts
      )
      next nil if year.nil?
      next nil unless CompanyProposalEnrichmentService.entity_match?(company, cand["source_url"], evidence_text: cand["evidence_text"]) # SPEC C

      { year: year, source_url: cand["source_url"], evidence_text: cand["evidence_text"], tier: CompanyProposalEnrichmentService.source_tier(cand["source_url"], company: company) } # SPEC D
    end
  end

  def evidence_hosts(research_payload)
    urls = Array(research_payload["results"]).map { |r| r["url"] }
    urls << company.main_url
    urls.compact_blank.filter_map { |url| CompanyProposalEnrichmentService.host_for(url) }.uniq
  end

  # Ranking = SPEC D tier order, then original collection order.
  def choose_candidate(candidates)
    tier_rank = { registry: 0, profile: 1, owned: 2, other: 3 }
    candidates.each_with_index.min_by { |c, i| [tier_rank.fetch(c[:tier], 99), i] }&.first
  end

  def record_provenance!(chosen)
    # Mirror the shape produced by CompanyProposalEnrichmentService#founded_year_provenance,
    # persisted on the company (add a jsonb column `founded_year_provenance` if not present;
    # otherwise store under the existing agent_details-like column — verify before writing).
    provenance = {
      "source_url" => chosen[:source_url],
      "source_tier" => chosen[:tier].to_s,
      "mode" => "server_backfill",
      "generated_at" => Time.current.utc.iso8601
    }
    if company.respond_to?(:founded_year_provenance=)
      company.update_columns(founded_year_provenance: provenance)
    end
  end

  def audit!(chosen)
    PipelineRun.create!(
      name: "Backfill founded_date",
      run_type: "founded_date_backfill",
      status: "succeeded",
      agent_name: "CompanyFoundedDateBackfillService",
      records_processed: 1,
      started_at: Time.current,
      finished_at: Time.current,
      details: { "company_id" => company.id, "year" => chosen[:year], "source_url" => chosen[:source_url], "source_tier" => chosen[:tier].to_s }
    )
  rescue StandardError => e
    Rails.logger.debug("[CompanyFoundedDateBackfillService] audit failed: #{e.message}")
    nil
  end
end
```

**Research entry point note** — `CompanyProposalResearchService.call` currently takes `proposal:` (verify in that file). Add a second entry point `.call(company:)` that builds an internal payload equivalent from `company.name` + `company.main_url` and returns the same shape (`"results" => [...]`, `"summary" => ...`, plus a `"candidates" => [{year, source_url, evidence_text}, ...]` list — extend the LLM prompt to emit this candidates list explicitly, or synthesize it deterministically from the free-text `summary` if the existing prompt already yields structured evidence). Do NOT fork the class into a second file; add the keyword-args entry point alongside the existing one.

**`app/jobs/backfill_founded_date_job.rb`** — new, mirroring `app/jobs/enrich_proposal_job.rb` byte-for-byte in shape:

```ruby
class BackfillFoundedDateJob < ApplicationJob
  queue_as :default

  # Runs founded_date backfill off the request thread so it is not bound by the
  # 30s HTTP router timeout. Delegates to CompanyFoundedDateBackfillService, which
  # reuses the same cite-only guard as proposal enrichment.
  def perform(company_id, admin_user_id = nil)
    company = Company.find_by(id: company_id)
    return unless company

    admin_user = AdminUser.find_by(id: admin_user_id) || Mcp::CuratorActor.admin_user!
    CompanyFoundedDateBackfillService.call(company: company, admin_user: admin_user)
  rescue StandardError => e
    Rails.logger.debug("[BackfillFoundedDateJob] backfill failed for company #{company_id}: #{e.message}")
  end
end
```

**`app/mcp/tools/backfill_founded_dates_tool.rb`** — new MCP wrapper:

```ruby
module Mcp
  module Tools
    class BackfillFoundedDatesTool < BaseTool
      tool_name "backfill_founded_dates"
      title "Backfill founded_date on companies"
      description "Enqueue N asynchronous server-side founded_date backfills across companies where founded_date is blank. Each job runs the same cite-only guard used by proposal enrichment and only writes a year when a real source states it. Poll get_company to observe results."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Backfill founded_date on companies")
      input_schema(
        properties: {
          limit: { type: "integer", description: "How many companies to enqueue (1-50, default 10)." }
        },
        required: []
      )

      def self.call(server_context:, limit: 10)
        capped = [[limit.to_i, 1].max, 50].min
        company_ids = Company.missing_founded_date.limit(capped).pluck(:id)
        company_ids.each { |id| BackfillFoundedDateJob.perform_later(id, curator.id) }

        audit!(action: "backfill_founded_dates", summary: "Enqueued #{company_ids.size} founded_date backfills", records_processed: company_ids.size, details: { "company_ids" => company_ids })

        json_response("result" => "enqueued", "enqueued" => company_ids.size, "company_ids" => company_ids)
      end
    end
  end
end
```

**`app/mcp/tools.rb`** — register in the ordered list under the "Maintenance of existing entries" section, right after `UpdateCompanyFieldTool`:

```ruby
UpdateCompanyFieldTool,
BackfillFoundedDatesTool,
ApplySafeFieldsTool,
```

**`lib/tasks/data_quality.rake`** — append inside `namespace :data_quality do` following the exact `backfill_identity` idiom (line 80-108 of the file):

```ruby
desc "Backfill missing founded_date values from web-cited sources. Defaults to dry-run; set DRY_RUN=false to enqueue jobs. INLINE=true to run synchronously (small batches only). LIMIT=n caps the batch."
task backfill_founded_dates: :environment do
  dry_run = ENV.fetch("DRY_RUN", "true") != "false"
  inline = ENV.fetch("INLINE", "false") == "true"
  verbose = ENV.fetch("VERBOSE", "false") == "true"
  limit = ENV.fetch("LIMIT", "50").to_i
  filled = 0
  skipped = Hash.new(0)
  examples = []

  scope = Company.missing_founded_date.limit(limit)

  scope.find_each do |company|
    if dry_run
      line = "DRY RUN company_id=#{company.id} name=#{company.name.inspect} main_url=#{company.main_url.inspect}"
      verbose ? puts(line) : (examples << line if examples.size < 20)
      skipped["dry_run"] += 1
      next
    end

    if inline
      result = CompanyFoundedDateBackfillService.call(company: company)
      case result["result"]
      when "filled"
        filled += 1
        puts "FILLED company_id=#{company.id} year=#{result['year']} source=#{result['source_url']} tier=#{result['source_tier']}" if verbose
      else
        skipped[result["result"]] += 1
        puts "SKIP company_id=#{company.id} result=#{result['result']} reason=#{result['reason']}" if verbose
      end
    else
      BackfillFoundedDateJob.perform_later(company.id)
      skipped["enqueued"] += 1
    end
  end

  mode = dry_run ? "dry-run" : (inline ? "inline" : "enqueued")
  puts examples if dry_run && !verbose
  puts "Backfill founded_date complete mode=#{mode} limit=#{limit} filled=#{filled} skipped=#{skipped.sort.to_h}"
end
```

### Acceptance criteria
- `rake data_quality:backfill_founded_dates` (default = dry-run) prints a plan and writes nothing; `Company.pluck(:founded_date)` unchanged before/after.
- `DRY_RUN=false INLINE=true LIMIT=3 rake data_quality:backfill_founded_dates` fills only companies where the cite-only guard passes; each filled company has a non-blank `founded_date` AND a corresponding `PipelineRun` with `run_type: "founded_date_backfill"` carrying `source_url` in `details`.
- `BackfillFoundedDatesTool.call(server_context:, limit: 3)` enqueues exactly 3 `BackfillFoundedDateJob`s and returns `{"result" => "enqueued", "enqueued" => 3, "company_ids" => [...]}`.
- New service test (`test/services/company_founded_date_backfill_service_test.rb`) stubs `CompanyProposalResearchService.call(company: ...)` to return a payload with (a) a registry-hosted candidate for company A → asserts `result` is `"filled"`, year set, `PipelineRun` written, `founded_year_provenance` recorded; (b) a payload with no candidates in evidence hosts → asserts `"skipped_no_source"` and `founded_date` still blank.
- New tool test in `test/mcp/curator_tools_test.rb` mirrors the existing `enrich_proposal queues async enrichment...` test using `assert_enqueued_with(job: BackfillFoundedDateJob)`.
- Existing proposal-enrichment tests (`CompanyProposalWorkflowTest`, the `sourced_year` tests in `CuratorToolsTest`) still pass unchanged.
- `UpdateCompanyFieldTool` behavior externally unchanged — its own two tests at `test/mcp/curator_tools_test.rb:325-341` still pass.

### Non-goals
- Do not add UI. This is server-only.
- Do not change proposal enrichment. The new service is a separate consumer of `sourced_year`.
- Do not add env-driven config beyond the existing `DRY_RUN` / `VERBOSE` / `LIMIT` / `INLINE` pattern.

---

## Spec C — Same-name-entity guard for founded_date sourcing

### Goal
Prevent the "APUA-India-vs-Finland" trap: a candidate year cited from `apualegal.com` must not be accepted for a company whose `main_url` is `apua.ai`. Today `sourced_year` in `app/services/company_proposal_enrichment_service.rb:23-33` only checks that the *host* is among gathered evidence — that is necessary but not sufficient when the wrong entity happens to appear in the same search bundle.

### Files to change
- `app/services/company_proposal_enrichment_service.rb` — add `entity_match?`, wire it into candidate acceptance
- `test/services/company_proposal_workflow_test.rb` — two new regression tests

### What to add/change

**`app/services/company_proposal_enrichment_service.rb`** — mirror the canonical-domain match in `CompanyDiscoverySearchService#cited_source_url` (`app/services/company_discovery_search_service.rb:287-299`). Add a class method:

```ruby
# Known registry/profile hosts we accept when the evidence text explicitly names the company.
ENTITY_REGISTRY_HOSTS = %w[
  linkedin.com
  crunchbase.com
  opencorporates.com
  companieshouse.gov.uk
  sec.gov
  bizfileonline.sos.ca.gov
  handelsregister.de
].freeze

# True when the citing source is (a) on the company's own canonical domain, or
# (b) on a known registry/profile host AND the surrounding evidence text explicitly
# names the company. This blocks year candidates cited from same-name but different
# entities (e.g. apualegal.com for a company whose canonical domain is apua.ai).
def self.entity_match?(company_or_proposal, source_url, evidence_text: nil)
  return false if source_url.blank?

  source_domain = Company.canonical_domain_for(source_url)
  return false if source_domain.blank?

  own_domain = own_canonical_domain(company_or_proposal)
  return true if own_domain.present? && (source_domain == own_domain || source_domain.end_with?(".#{own_domain}") || own_domain.end_with?(".#{source_domain}"))

  return false unless ENTITY_REGISTRY_HOSTS.any? { |h| source_domain == h || source_domain.end_with?(".#{h}") }

  name = display_name_for(company_or_proposal)
  return false if name.blank? || evidence_text.blank?

  evidence_text.to_s.downcase.include?(name.downcase)
end

def self.own_canonical_domain(record)
  main_url = if record.respond_to?(:canonical_main_domain)
    return record.canonical_main_domain
  elsif record.respond_to?(:final_changes)
    record.final_changes["main_url"] || record.source_payload["website"]
  end
  Company.canonical_domain_for(main_url)
end

def self.display_name_for(record)
  return record.name if record.respond_to?(:name) && record.name.present?
  record.respond_to?(:display_name) ? record.display_name : nil
end
```

Then, where `sourced_founded_year` picks a candidate (line 104-114), add the entity gate on top of the existing `sourced_year` gate:

```ruby
def sourced_founded_year
  return if proposal.final_changes["founded_date"].present?

  candidate_source = llm_payload["founded_year_source"]
  candidate_evidence = llm_payload["founded_year_evidence_text"] # extend the LLM prompt to return this alongside founded_year_source

  year = self.class.sourced_year(
    year: llm_payload["founded_year"],
    source: candidate_source,
    allowed_hosts: evidence_hosts
  )
  return nil if year.blank?
  return nil unless self.class.entity_match?(proposal, candidate_source, evidence_text: candidate_evidence)

  @founded_year_source = candidate_source
  year
end
```

Extend the LLM instruction string in `description_prompt` (line 207-213) to also emit `founded_year_evidence_text` — a short verbatim snippet from the cited source that mentions the company. When absent, `entity_match?` returns false for registry hosts (safe default).

### Acceptance criteria
- New test in `CompanyProposalWorkflowTest` — "sourced_year rejects same-name entity from a different domain":
    - Proposal name = "APUA", main_url = "https://apua.ai".
    - `llm_payload` stubbed with `founded_year: "2015"`, `founded_year_source: "https://apualegal.com/about"`, `founded_year_evidence_text: "APUA Legal was founded in 2015..."`.
    - `research_payload` stubbed with `apualegal.com` in results (so the current `sourced_year` gate alone would accept it).
    - Assert `proposal.final_changes["founded_date"]` is nil after enrichment.
- New test — "sourced_year rejects Firmly Seattle vs firmly.in.th":
    - Proposal name = "Firmly", main_url = "https://firmly.co" (Seattle-based).
    - Candidate source = `https://firmly.in.th/about`, evidence text names the Thai firm.
    - Assert `founded_date` is nil.
- New test — "sourced_year accepts a linkedin.com citation when the evidence text names this company": positive path — `founded_year_source: "https://www.linkedin.com/company/apua-ai"`, evidence text `"APUA · ai-native contract intelligence · Founded 2023"`, main_url `apua.ai`. Assert year set to `"2023"`.
- Existing `sourced_year accepts a plausible year cited by gathered evidence` (`test/mcp/curator_tools_test.rb:298-301`) still passes — the class-method `sourced_year` signature is unchanged; the entity guard is a *second* gate applied at the caller.
- All existing enrichment tests still pass.

### Non-goals
- Do not modify `CompanyDiscoverySearchService#cited_source_url` — it is the *pattern*, and it's correct as-is for discovery-time.
- Do not build a fuzzy name matcher — a case-insensitive substring on the display name is sufficient for the identified traps.

---

## Spec D — Registry-preference tiering

### Goal
When multiple year candidates survive the SPEC C entity guard, prefer registry > profile > owned > other, then earlier collection order. Store the chosen tier in provenance so audits can see why a source won.

### Files to change
- `app/services/company_proposal_enrichment_service.rb` — `source_tier` helper, use it in ranking + provenance
- `app/services/company_founded_date_backfill_service.rb` — already ranks by tier per SPEC B (this spec just supplies the helper)
- `test/services/company_proposal_workflow_test.rb` — new ranking test

### What to add/change

**`app/services/company_proposal_enrichment_service.rb`** — add constants and helper:

```ruby
REGISTRY_HOSTS = %w[
  opencorporates.com
  companieshouse.gov.uk
  sec.gov
  bizfileonline.sos.ca.gov
  handelsregister.de
].freeze

PROFILE_HOSTS = %w[
  linkedin.com
  crunchbase.com
].freeze

# Returns :registry, :profile, :owned, or :other for a candidate source_url.
# Used to break ties between multiple entity-matched founding-year candidates.
def self.source_tier(source_url, company: nil)
  domain = Company.canonical_domain_for(source_url)
  return :other if domain.blank?

  return :registry if REGISTRY_HOSTS.any? { |h| domain == h || domain.end_with?(".#{h}") }
  return :profile  if PROFILE_HOSTS.any?  { |h| domain == h || domain.end_with?(".#{h}") }

  own = company&.respond_to?(:canonical_main_domain) ? company.canonical_main_domain : nil
  return :owned if own.present? && (domain == own || domain.end_with?(".#{own}") || own.end_with?(".#{domain}"))

  :other
end
```

In `founded_year_provenance` (line 124-128), include the tier:

```ruby
def founded_year_provenance
  return nil if @founded_year_source.blank?

  {
    "source_url" => @founded_year_source,
    "source_tier" => self.class.source_tier(@founded_year_source, company: nil).to_s,
    "mode" => "web_research_cited",
    "generated_at" => Time.current.utc.iso8601
  }
end
```

If `sourced_founded_year` ever needs to rank multiple candidates (currently the LLM emits a single `founded_year_source`; if you extend the prompt to emit `founded_year_candidates: [{year, source_url, evidence_text}, ...]`), sort by `[tier_rank, collection_index]` the same way `CompanyFoundedDateBackfillService#choose_candidate` does. Reuse the same `tier_rank` map — do not duplicate.

### Acceptance criteria
- Unit test in `CompanyProposalWorkflowTest`: given three candidates for the same company — `{year: "2018", source_url: "https://opencorporates.com/companies/us/x"}`, `{year: "2020", source_url: "https://www.linkedin.com/company/x"}`, `{year: "2019", source_url: "https://x.com/about"}` — the chosen candidate is the OpenCorporates one (registry wins). Assert `founded_year_provenance["source_tier"] == "registry"`.
- Tie-breaker test: two registry sources, earlier one wins.
- Provenance JSON on any newly-filled record shows one of the four tier strings.
- `CompanyProposalEnrichmentService.source_tier("https://www.linkedin.com/x")` → `:profile`; `source_tier("https://opencorporates.com/x")` → `:registry`; `source_tier("https://apua.ai/about", company: apua_company)` → `:owned`; `source_tier("https://example.com/x")` → `:other`.
- Existing tests unchanged.

### Non-goals
- No config file for host lists. `REGISTRY_HOSTS` / `PROFILE_HOSTS` / `ENTITY_REGISTRY_HOSTS` are plain constants (no env, no YAML).
- Do not rerank *already-published* companies — the tier is captured going forward, not backfilled onto historical writes.

---

## How to test

Run these specific files after implementing each spec:

- `bin/rails test test/models/company_test.rb` — Spec A scope test.
- `bin/rails test test/services/company_proposal_workflow_test.rb` — Specs C and D regression tests (APUA, Firmly, tier ranking).
- `bin/rails test test/services/company_founded_date_backfill_service_test.rb` — Spec B service test (new file).
- `bin/rails test test/mcp/curator_tools_test.rb` — Spec A search filter + get_stats field, Spec B `BackfillFoundedDatesTool` enqueue test; also confirms unchanged tests still pass (`update_company_field...`, `sourced_year...`, `founding year is optional and does not block publishing`).
- `bundle exec rake data_quality:backfill_founded_dates` — dry-run smoke test.
- `DRY_RUN=false INLINE=true LIMIT=1 bundle exec rake data_quality:backfill_founded_dates` — end-to-end live smoke on one company (only run against a scratch DB or after reviewing which company will be touched).