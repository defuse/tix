class TicketDisplayWrapper

  attr_accessor :ticket

  def initialize( ticket, &to_s )
    @ticket = ticket
    @to_s = to_s
  end

  def to_s
    @to_s.call( @ticket )
  end

end
