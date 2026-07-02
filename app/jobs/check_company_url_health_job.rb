class CheckCompanyUrlHealthJob < ApplicationJob
  queue_as :default

  # Runs a company's URL health probe off the request thread (Solid Queue) so a
  # large maintenance sweep drains reliably without hitting the HTTP router timeout.
  def perform(company_id)
    company = Company.find_by(id: company_id)
    return unless company

    CompanyUrlHealthCheckService.call(company: company)
  rescue StandardError => e
    Rails.logger.debug("[CheckCompanyUrlHealthJob] url check failed for company #{company_id}: #{e.message}")
  end
end
