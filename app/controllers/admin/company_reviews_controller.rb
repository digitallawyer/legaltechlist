module Admin
  class CompanyReviewsController < BaseController
    def show
      @company = Company.includes(:category, :secondary_category, :successor_company, :business_models, :target_clients, :target_client, :tags).find(params[:id])
      @duplicate_domain_companies = duplicate_domain_companies
      @duplicate_name_companies = duplicate_name_companies
      @company_pipeline_runs = PipelineRun.for_company(@company).recent.limit(10)
      @agent_review = AgentReviewPacket.latest_agent_review_for(@company)
      @duplicate_review = AgentReviewPacket.latest_duplicate_review_for(@company)
    end

    def create_agent_review
      company = Company.find(params[:id])
      CompanyAgentReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from custom company review page")

      redirect_to custom_admin_company_review_path(company.id, anchor: "agent-review"),
                  notice: "Agent review complete for #{company.name}. The findings are below."
    end

    def create_next_description_review
      company = Company.description_review_candidates.order(updated_at: :asc).first
      return redirect_to custom_admin_companies_path(review_signal: "description_review"), alert: "No description review candidates found." unless company

      run = CompanyAgentReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from next description review queue")

      redirect_to custom_admin_agent_review_path(run), notice: "Description review created for #{company.name}."
    end

    def create_duplicate_review
      company = Company.find(params[:id])
      DuplicateDomainReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from custom company review page")

      redirect_to custom_admin_company_review_path(company.id, anchor: "duplicate-review"),
                  notice: "Duplicate review complete for #{company.name}. The findings are below."
    end

    def create_next_duplicate_domain_review
      company = Company.duplicate_domain_candidates.order(updated_at: :asc).first
      return redirect_to custom_admin_companies_path(review_signal: "duplicate_domain"), alert: "No duplicate-domain candidates found." unless company

      run = DuplicateDomainReviewService.call(company: company, reviewer: current_admin_user.email, notes: "Triggered from next duplicate-domain review queue")

      redirect_to custom_admin_agent_review_path(run), notice: "Duplicate-domain review created for #{company.name}."
    end

    def mark_review
      company = Company.find(params[:id])
      decision = params[:decision].to_s
      CompanyReviewMarkService.call(
        company: company,
        decision: decision,
        admin_user: current_admin_user,
        instructions: params[:contributor_instructions],
        fields: params[:contributor_fields]
      )

      # A record handed back to its contributor has left this reviewer's queue, so land
      # on the queue rather than the record they no longer need to act on.
      if decision == "return_to_contributor"
        return redirect_to custom_admin_companies_path(review_state: "awaiting_contributor"),
                           notice: "#{company.name} was returned to its contributor and is no longer in the review queue."
      end

      if decision.in?(%w[verified reject])
        return redirect_to custom_admin_companies_path,
                           notice: "#{mark_review_notice(decision, company.name)} It has left the review queue."
      end

      redirect_to custom_admin_company_review_path(company.id), notice: mark_review_notice(decision, company.name)
    rescue ArgumentError => e
      redirect_to custom_admin_company_review_path(company.id), alert: e.message
    end

    private

    def mark_review_notice(decision, company_name)
      case decision
      when "verified" then "#{company_name} marked as verified."
      when "needs_work" then "#{company_name} marked as needing more review."
      when "reject" then "#{company_name} rejected and hidden."
      else "Review status updated for #{company_name}."
      end
    end

    def duplicate_domain_companies
      Company.duplicates_by_domain_for(@company)
    end

    def duplicate_name_companies
      Company.duplicates_by_normalized_name_for(@company)
    end
  end
end
