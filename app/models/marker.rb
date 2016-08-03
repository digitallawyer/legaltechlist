#Made in image of Gmaps4rails 
class Marker
	def initialize(collection)
		@collection = {}
	    collection.each do |company|
	    	@collection[company.name] = company
	    end
	end

	def call(&block)
    	@collection.each_pair do |key, val|
        	@collection[key] = MarkerBuilder.new(val).call(&block)
      	end
    end

    class MarkerBuilder

		attr_reader :object, :hash
		def initialize(object)
	        @object = object
	        @hash   = {}
	    end

	    def call(&block)
	        block.call(object, self)
	        hash
	    end

	    def lat(float)
	        @hash[:lat] = float
	    end

		def lng(float)
	    	@hash[:lng] = float
	 	end

		def infowindow(string)
			@hash[:infowindow] = string
		end

		def title(string)
			@hash[:marker_title] = string
		end

		def json(hash)
			@hash.merge! hash
		end

		def picture(hash)
			@hash[:picture] = hash
		end

		def shadow(hash)
			@hash[:shadow] = hash
		end
	end
end