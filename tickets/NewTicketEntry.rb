require 'core/Database.rb'
require 'tickets/TicketEntry.rb'

class NewTicketEntry < TicketEntry

  def initialize( ticketId )
    @ticketId = ticketId
  end

  def commit
    Database::DB.execute(
      "INSERT INTO entries (ticket_id, entry_text, user, minutes_spent, change_time)
        VALUES (:ticket_id, :text, :user, :minutes, :time)",
      :ticket_id => @ticketId,
      :text => @text,
      :user => @user,
      :minutes => @minutes,
      :time => Time.now.to_i,
    )
  end

end
