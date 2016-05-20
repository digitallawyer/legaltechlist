class ApplicationMailer < ActionMailer::Base
  default from: "no-reply@tech.law.stanford.edu"
  layout 'mailer'
end
