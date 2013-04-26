
class TicketEntry
  attr_accessor :user, :text, :minutes, :time

  def initialize( ticket = nil )
    @user = ""
    @text = ""
    @minutes = 0
    @time = Time.at( 0 )
  end

  def self.getAllTicketEntries( ticketId )
    # id is a autoincrement primary key, so to get the list of entries in 
    # reverse-chronological order, we just have to order by id DESC
    entryRows = Database::DB.execute(
      "SELECT * FROM entries WHERE ticket_id = :ticket_id ORDER BY id DESC",
      :ticket_id => ticketId
    )

    entryRows.map do |row|
      entry = TicketEntry.new
      entry.text = row['entry_text']
      entry.user = row['user']
      entry.minutes = row['minutes_spent']
      entry.time = Time.at( row['change_time'].to_i )
      entry
    end
  end

end
