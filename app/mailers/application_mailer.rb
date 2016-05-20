class ApplicationMailer < ActionMailer::Base
  default from: "no-reply@codex.stanford.edu"
  layout 'mailer'
end
