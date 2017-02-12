class InvalidPage < StandardError
	def initialize(msg="Invalid person or course page.")
		super
  end
end