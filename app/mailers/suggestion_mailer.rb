class SuggestionMailer < ApplicationMailer
  default from: 'do_not_reply@legaltechlist'
  
  def newcompany_email(company)
    puts "====================================================================="
    puts "Execute new company e-mail:"
    puts company
    puts "====================================================================="
    
    @company = company
    @message = "Hello! Add this company!"
    mail(to: 'hello@markharrisevans.com', subject: 'Test e-mail')
  end
  
  def editcompany_email(company)
    puts "====================================================================="
    puts "Execute edit company e-mail:"
    puts company
    puts "====================================================================="
    
    @company = company
    @message = "Hello! Edit this company!"
    mail(to: 'hello@markharrisevans.com', subject: 'Test e-mail')
  end

end
