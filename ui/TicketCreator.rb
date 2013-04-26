require 'etc'
require 'tickets/Ticket.rb'
require 'ui/TicketEditor.rb'
require 'tickets/TicketChange.rb'
require 'core/User.rb'

class TicketCreator < TicketEditor

  def initialize
    super( nil )
  end

  def commit( change )
    ticket = Ticket.createNew
    begin
      ticket.commitChange( change, User.getlogin )
      return true
    rescue TicketChange::InvalidAttributeError => e
      ticket.delete
      @flash = "  ********* ERROR: #{e.message} *********"
      return false
    end
  end
end
