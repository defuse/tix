require 'core/Database.rb'

class ListItem

  class NoSuchListItemError < StandardError; end 

  attr_reader :id, :shortName, :description

  def initialize( id, shortName, description )
    @id = id
    @shortName = shortName.strip
    @description = description.strip
  end

  def to_s
    if @description.nil? or @description.empty?
      @shortName
    else
      @shortName + " - " + @description
    end
  end

  def ==( x )
    return false unless x.kind_of? ListItem
    return @id == x.id && @shortName == x.shortName && @description == x.description
  end

  def <=>( x )
    self.shortName.<=>( x.shortName )
  end

  def self.tableName
    raise 'Must be subclassed.'
  end

  def self.allItems
    Database::DB.execute( "SELECT id, name, description FROM #{self.tableName}" ).map do |row|
      self.new( row['id'], row['name'], row['description'] )
    end
  end

  def self.fromId( id )
    results = Database::DB.execute(
      "SELECT id, name, description FROM #{self.tableName} WHERE id = :id",
      :id => id
    )
    if results.empty?
      raise NoSuchListItemError.new( 'No such list item' )
    end
    return self.new( results[0]['id'], results[0]['name'], results[0]['description'] )
  end

end
