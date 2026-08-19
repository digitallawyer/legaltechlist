require "date"

# Records an acquisition on a company: sets status=acquired, captures the acquirer
# (free-text name + optional URL, so buyers outside the index are tracked), links an
# in-index successor when supplied, and stores the acquisition date with its precision
# plus the announcement source_url in acquisition_details. Shared by record_acquisition
# and approve_proposal so historical entries publish straight into the acquired state.
class CompanyAcquisitionService
  Result = Struct.new(:company, :applied, keyword_init: true)

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company:, acquirer_name:, acquirer_url: nil, acquired_on: nil, successor: nil, source_url: nil, save: true)
    @company = company
    @acquirer_name = acquirer_name.to_s.strip
    @acquirer_url = acquirer_url.presence
    @acquired_on = acquired_on
    @successor = successor
    @source_url = source_url.presence
    @save = save
  end

  def call
    raise ArgumentError, "acquirer_name is required" if acquirer_name.blank?
    raise ArgumentError, "acquirer_url must be an http(s) URL" if acquirer_url.present? && !valid_http_url?(acquirer_url)
    raise ArgumentError, "A company cannot be its own successor" if successor && successor.id == company.id

    date, precision = parse_date(acquired_on)
    raise ArgumentError, "acquired_on must be YYYY or YYYY-MM-DD" if acquired_on.present? && date.nil?

    company.status = "acquired"
    company.acquirer_name = acquirer_name
    company.acquirer_url = acquirer_url
    company.successor_company_id = successor.id if successor
    company.exit_date = date if date
    company.acquisition_details = acquisition_details(precision)
    company.save! if save

    Result.new(company: company, applied: applied(date, precision))
  end

  private

  attr_reader :company, :acquirer_name, :acquirer_url, :acquired_on, :successor, :source_url, :save

  def acquisition_details(precision)
    existing = company.acquisition_details.is_a?(Hash) ? company.acquisition_details : {}
    existing.merge(
      "source_url" => source_url,
      "date_precision" => precision,
      "recorded_at" => Time.current.utc.iso8601
    ).compact
  end

  def applied(date, precision)
    {
      "status" => "acquired",
      "acquirer_name" => acquirer_name,
      "acquirer_url" => acquirer_url,
      "acquired_on" => date&.iso8601,
      "date_precision" => precision,
      "successor_company_id" => successor&.id,
      "successor_slug" => successor&.slug,
      "source_url" => source_url
    }.compact
  end

  # Accepts a bare 4-digit year (stored as Jan 1, precision "year") or a full ISO
  # date (precision "day"). Returns [Date, precision] or [nil, nil].
  def parse_date(value)
    raw = value.to_s.strip
    return [nil, nil] if raw.blank?
    return [Date.new(raw.to_i, 1, 1), "year"] if raw.match?(/\A(?:19|20)\d{2}\z/)

    [Date.iso8601(raw), "day"]
  rescue ArgumentError
    [nil, nil]
  end

  def valid_http_url?(value)
    uri = URI.parse(value.to_s.strip)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
