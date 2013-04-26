require 'tickets/ListItem.rb'

class Status < ListItem
  def self.tableName
    "statuses"
  end
end
