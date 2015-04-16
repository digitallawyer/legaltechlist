class Company < ActiveRecord::Base

	def self.text_search(query)
		if query.present?
			search(query)
		else
			scoped
		end
	end

end
