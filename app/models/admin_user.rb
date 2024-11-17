class AdminUser < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, 
         :recoverable, :rememberable, :trackable, :validatable

  def self.ransackable_attributes(auth_object = nil)
    %w[id email created_at updated_at last_sign_in_at sign_in_count 
       current_sign_in_at last_sign_in_ip current_sign_in_ip]
  end
end
