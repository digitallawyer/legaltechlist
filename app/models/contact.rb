class Contact < ActiveRecord::Base
  validates :name, presence: true, length: {minimum: 3}
  validates :email, presence: true, format: {with: /\A[-a-z0-9_+\.]+\@([-a-z0-9]+\.)+[a-z0-9]{2,4}\z/i, message: "must be e-mail format"}
 
end
