require 'tickets/ListItem.rb'

class Project < ListItem
  def self.tableName
    "projects"
  end
end
