class CompanyAgentReviewJob < ApplicationJob
  queue_as :default

  # Runs one company's agent review off the request thread. A batch of these is how the
  # Company tab offers "review these five" without holding a web request open for five
  # sequential LLM passes, and a failure on one company leaves the rest untouched.
  def perform(company_id, reviewer_email = nil)
    company = Company.find_by(id: company_id)
    return unless company

    CompanyAgentReviewService.call(
      company: company,
      reviewer: reviewer_email,
      notes: "Queued from a Company tab batch review"
    )
  rescue StandardError => e
    Rails.logger.debug("[CompanyAgentReviewJob] review failed for company #{company_id}: #{e.class}: #{e.message}")
    PipelineRun.create!(
      name: "Agent company review failed: #{company&.name || company_id}",
      run_type: "company_agent_review",
      status: "failed",
      agent_name: "CompanyAgentReviewJob",
      records_processed: 0,
      details: { "company_id" => company_id, "error_class" => e.class.name, "error_message" => e.message }
    )
  end
end
