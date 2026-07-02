require "net/http"
require "uri"

# Probes a company's main_url and records a coarse health verdict used as a QC/
# maintenance signal for spotting companies that may have gone inactive. It never
# changes a company's lifecycle status — a broken URL is a soft indicator surfaced
# for curator review.
#
# Verdicts (stored on Company#url_status):
#   "ok"      – the site responded successfully (2xx, or a redirect chain ending 2xx)
#   "unknown" – the site is up but we can't confirm content health (401/403/429
#               bot-blocks, or a single transient failure below the flap threshold)
#   "broken"  – the URL is gone/unreachable across FAILURE_THRESHOLD consecutive checks
#
# A consecutive-failure counter (persisted in Company#url_health) prevents a single
# transient blip from flagging a live site.
class CompanyUrlHealthCheckService
  OPEN_TIMEOUT = 6
  READ_TIMEOUT = 10
  MAX_REDIRECTS = 5
  # Only escalate to "broken" after this many consecutive failing checks so a lone
  # transient outage does not flag a healthy company.
  FAILURE_THRESHOLD = 2
  USER_AGENT = "CodeX-TechIndex-LinkChecker/1.0 (+https://techindex.law.stanford.edu)".freeze

  # Response codes that mean "the server is up but is blocking automated access" —
  # common for Cloudflare/WAF-protected but perfectly live sites. Treated as
  # inconclusive, never as broken.
  BOT_BLOCK_CODES = [401, 403, 405, 406, 429].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  # Convenience for the recurring sweep / rake task: enqueue up to `limit` due checks.
  def self.enqueue_due(limit: 200, cooldown: 30.days)
    ids = Company.url_check_due(cooldown).order(Arel.sql("url_checked_at ASC NULLS FIRST")).limit(limit).pluck(:id)
    ids.each { |id| CheckCompanyUrlHealthJob.perform_later(id) }
    ids
  end

  def initialize(company:)
    @company = company
  end

  def call
    url = normalized_url
    return record_invalid! if url.nil?

    outcome = probe(url)
    persist!(outcome)
    outcome.merge("company_id" => company.id, "url_status" => company.url_status)
  end

  private

  attr_reader :company

  def normalized_url
    raw = company.main_url.to_s.strip
    return nil if raw.blank? || raw.casecmp?("n/a") || raw.casecmp?("unknown")

    raw = "http://#{raw}" unless raw.match?(%r{\Ahttps?://}i)
    uri = URI.parse(raw)
    uri.is_a?(URI::HTTP) && uri.host.present? ? uri : nil
  rescue URI::InvalidURIError
    nil
  end

  # Follows redirects manually (HEAD first, GET fallback) so we can capture the final
  # URL and status. Returns a normalized outcome hash.
  def probe(uri, redirects_left = MAX_REDIRECTS, method: :head)
    response = request(uri, method)

    case response
    when Net::HTTPRedirection
      location = redirect_target(uri, response["location"])
      return failure_outcome("redirect loop or missing Location", code: response.code.to_i) if location.nil? || redirects_left.zero?

      probe(location, redirects_left - 1, method: :head)
    when Net::HTTPSuccess
      success_outcome(code: response.code.to_i, final_url: uri.to_s)
    else
      code = response.code.to_i
      # Some servers reject HEAD (405/501) — retry once with GET before judging.
      return probe(uri, redirects_left, method: :get) if method == :head && [405, 501].include?(code)
      return inconclusive_outcome("server responded #{code} (access-restricted)", code: code, final_url: uri.to_s) if BOT_BLOCK_CODES.include?(code)

      failure_outcome("HTTP #{code}", code: code, final_url: uri.to_s)
    end
  rescue StandardError => e
    failure_outcome("#{e.class}: #{e.message}")
  end

  def request(uri, method)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.max_retries = 0

    request_class = method == :head ? Net::HTTP::Head : Net::HTTP::Get
    req = request_class.new(uri.request_uri.presence || "/")
    req["User-Agent"] = USER_AGENT
    req["Accept"] = "*/*"
    http.request(req)
  end

  def redirect_target(current_uri, location)
    return nil if location.blank?

    target = URI.join(current_uri.to_s, location)
    target.is_a?(URI::HTTP) && target.host.present? ? target : nil
  rescue URI::InvalidURIError
    nil
  end

  def success_outcome(code:, final_url:)
    { "result" => Company::URL_STATUS_OK, "status_code" => code, "final_url" => final_url }
  end

  def inconclusive_outcome(reason, code: nil, final_url: nil)
    { "result" => Company::URL_STATUS_UNKNOWN, "status_code" => code, "final_url" => final_url, "reason" => reason }
  end

  def failure_outcome(reason, code: nil, final_url: nil)
    { "result" => "failure", "status_code" => code, "final_url" => final_url, "reason" => reason }
  end

  def record_invalid!
    persist!(inconclusive_outcome("no usable main_url"))
    { "company_id" => company.id, "url_status" => company.url_status, "result" => "invalid_url" }
  end

  # Writes the verdict with update_columns to bypass validations/callbacks (the
  # record may be otherwise-invalid, and we must not trigger geocoding/logo fetches).
  def persist!(outcome)
    failing = outcome["result"] == "failure"
    prior_failures = company.url_health&.dig("consecutive_failures").to_i
    consecutive = failing ? prior_failures + 1 : 0

    url_status = if failing
      consecutive >= FAILURE_THRESHOLD ? Company::URL_STATUS_BROKEN : Company::URL_STATUS_UNKNOWN
    else
      outcome["result"]
    end

    health = {
      "consecutive_failures" => consecutive,
      "final_url" => outcome["final_url"],
      "reason" => outcome["reason"],
      "checked_at" => Time.current.utc.iso8601
    }
    health["last_ok_at"] = Time.current.utc.iso8601 if url_status == Company::URL_STATUS_OK
    health["last_ok_at"] ||= company.url_health&.dig("last_ok_at")

    company.update_columns(
      url_status: url_status,
      url_status_code: outcome["status_code"],
      url_checked_at: Time.current,
      url_health: health.compact
    )
  end
end
