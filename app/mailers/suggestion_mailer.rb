class SuggestionMailer < ApplicationMailer
  default from: 'no-reply@codex.stanford.edu'
  
  #send a new company e-mail with the parameters passed in
  def newcompany_email(company)
    @company = company
    @message = "New Legal Tech Company Suggested"
    
    AdminUser.all.each do |admin|
      mail(to: admin.email, subject: 'LegalTechList: New Company Suggestion')
    end
  end
  
  # send an edit company e-mail with the paramaters passed in
  def editcompany_email(company)
    @company = company
    @message = "Correction submitted for Legal Tech Company."
    
    AdminUser.all.each do |admin|
      mail(to: admin.email, subject: 'LegalTechList: Company Correction')
    end
  end

end
