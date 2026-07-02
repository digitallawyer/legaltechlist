require "test_helper"
require "minitest/mock"
require "net/http"

class CompanyUrlHealthCheckServiceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @company.update_columns(status: "active", main_url: "http://example.com", url_status: nil, url_status_code: nil, url_checked_at: nil, url_health: nil)
  end

  def response(klass, code, location: nil)
    resp = klass.new("1.1", code, "")
    resp["location"] = location if location
    resp
  end

  def run_check(fake)
    service = CompanyUrlHealthCheckService.new(company: @company)
    service.stub(:request, fake) { service.call }
    @company.reload
  end

  test "records ok on a successful response" do
    result = run_check(response(Net::HTTPOK, "200"))
    assert_equal Company::URL_STATUS_OK, @company.url_status
    assert_equal 200, @company.url_status_code
    assert_equal 0, @company.url_consecutive_failures
    assert @company.url_checked_at.present?
    assert_equal Company::URL_STATUS_OK, result["url_status"]
  end

  test "treats a 403 bot-block as unknown, not broken" do
    run_check(response(Net::HTTPForbidden, "403"))
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal 0, @company.url_consecutive_failures
  end

  test "only escalates to broken after consecutive failures" do
    run_check(response(Net::HTTPNotFound, "404"))
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal 1, @company.url_consecutive_failures

    run_check(response(Net::HTTPNotFound, "404"))
    assert_equal Company::URL_STATUS_BROKEN, @company.url_status
    assert_equal 2, @company.url_consecutive_failures
    assert_equal 404, @company.url_status_code
  end

  test "a success resets the failure counter" do
    run_check(response(Net::HTTPNotFound, "404"))
    run_check(response(Net::HTTPNotFound, "404"))
    assert_equal Company::URL_STATUS_BROKEN, @company.url_status

    run_check(response(Net::HTTPOK, "200"))
    assert_equal Company::URL_STATUS_OK, @company.url_status
    assert_equal 0, @company.url_consecutive_failures
  end

  test "connection errors count as failures" do
    service = CompanyUrlHealthCheckService.new(company: @company)
    raiser = ->(_uri, _method) { raise SocketError, "getaddrinfo failed" }
    service.stub(:request, raiser) { service.call }
    @company.reload
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal 1, @company.url_consecutive_failures
    assert_match(/SocketError/, @company.url_health["reason"])
  end

  test "does not change lifecycle status" do
    run_check(response(Net::HTTPNotFound, "404"))
    run_check(response(Net::HTTPNotFound, "404"))
    assert_equal "active", @company.status
  end

  test "invalid main_url is recorded as unknown without a request" do
    @company.update_columns(main_url: "n/a")
    service = CompanyUrlHealthCheckService.new(company: @company)
    result = service.call
    @company.reload
    assert_equal "invalid_url", result["result"]
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
  end

  test "url_check_due excludes recently checked and resolved-status companies" do
    @company.update_columns(url_checked_at: 1.day.ago)
    assert_not_includes Company.url_check_due(30.days).to_a, @company

    @company.update_columns(url_checked_at: 60.days.ago)
    assert_includes Company.url_check_due(30.days).to_a, @company

    @company.update_columns(status: "acquired")
    assert_not_includes Company.url_check_due(30.days).to_a, @company
  end
end
