require 'core/Database.rb'
require 'tickets/Ticket.rb'
require 'tickets/Keyword.rb'
require 'tickets/Project.rb'
require 'tickets/Status.rb'

# Search query strings are composed of "primitives" combined using the boolean
# operators "OR" and "AND", and precedence brackets "(" and ")".
#
# The following primitives are supported:
#
#   Primitive    | Meaning
#  --------------+-------------------------------------------------------------
#   dddddd-ddd   | Ticket id = "dddddd-ddd"
#   d=xxx        | Description contains "xxx"
#   a=xxx        | Assigned to user "xxx"
#   k=xxx        | Has keyword "xxx"
#   l=xxx        | User "xxx" is listening
#   j=xxx        | Project "xxx"
#   s=xxx        | Status "xxx"
#   p=xxx        | Has priority "xxx"
#   h=xx.x       | Has "xx.x" hours of time logged (dot not required)
#   r=xx.x       | Has "xx.x" hours remaining (dot not required)
#
# Notes:
# - Primitives separated only by whitespace implies an AND between them
# - Values with braces or spaces MUST be quoted, e.g. d="foo( )bar"
#     - Escape double quotes with \" and backslashes with \\
# - The != operator can be used for all types, e.g. a!=foo
# - Relational operators (<=, >=, <, >) can be used for numeric types
# - All text types are case-insensitive
# - Description searching supports partial matching, e.g.
#       `d=bar' will match a ticket with description `foobarbaz'

class TicketSearch

  class InvalidSearchQueryError < StandardError; end

  QuotedCondition = /([a-z])(=|<=|>=|<|>|!=)"(.*[^\\])"/
  UnquotedCondition = /([a-z])(=|<=|>=|<|>|!=)(\S+)/

  # The default boolean operator between primitives separated only by whitespace
  DefaultJunciton = " AND "

  attr_reader :results

  def initialize( query )
    @results = nil
    @params = {}
    @paramNum = 0

    wherePart =  sqlizeQuery( query )
    @where = wherePart.strip.empty? ? "" : "WHERE " + wherePart
  end

  def runSearch
    @results = Database::DB.execute(
      "SELECT tickets.id FROM tickets " + @where + 
      " ORDER BY tickets.priority, tickets.project ASC",
       @params
    ).map do |row|
      Ticket.new( row[0] )
    end
  rescue SQLite3::SQLException
    raise InvalidSearchQueryError.new(
      'Malformed search query (check braces and boolean operators)'
    )
  end

  #############################################################################
  #                              QUERY PARSING                                #
  #############################################################################

  private

  def sqlizeQuery( query )
    sqlQuery = ""
    search = 0
    lastType = nil

    loop do
      primStart, primEnd = findNextPrimitive( query, search )
      primitive = query[primStart..primEnd]

      # If there are two search criteria in a row, we need to put a boolean 
      # operator in between them.
      case primitive
      when Ticket::TicketIdRegexp, QuotedCondition, UnquotedCondition
        if lastType == :search
          sqlQuery << DefaultJunciton
        end
        lastType = :search
      else
        lastType = nil
      end

      sqlQuery << getSqlEquivalent( query[primStart..primEnd] )
      search = primEnd + 1
    end # loop

    trailing = query[search...query.length].strip
    unless trailing.empty?
      raise InvalidSearchQueryError.new( "Junk trailing text: [#{trailing}]" )
    end

    return sqlQuery
  end

  def findNextPrimitive( query, start )
    primitive = %r{
      \(   | # Braces
      \)   |
      AND  | # Boolean operators
      OR           
    }x
    # Add the condition and ticket number primitives
    primitive = Regexp.union(
      primitive, 
      UnquotedCondition,
      QuotedCondition,
      Ticket::TicketIdRegexp
    )

    matchdata = primitive.match( query, start )
    raise StopIteration if matchdata.nil?
    between = query[start...matchdata.begin( 0 )].strip
    unless between.empty?
      raise InvalidSearchQueryError.new( "Junk text in query: [#{between}]" )
    end
    return [matchdata.begin( 0 ), matchdata.end( 0 ) - 1]
  end

  def getSqlEquivalent( primitive )
    case primitive
    when "(", ")", "AND", "OR"
      return " " + primitive + " "
    when Ticket::TicketIdRegexp
      return " tickets.id = #{param( primitive )} "
    when QuotedCondition
      return conditionToSql( $1, $2, deslash( $3 ) )
    when UnquotedCondition
      return conditionToSql( $1, $2, $3 )
    else
      raise InvalidSearchQueryError.new( "Invalid primitive" ) 
    end
  end

  def conditionToSql( field, relation, value )
    unless ["=", "<=", ">=", ">", "<", "!="].include? relation
      raise InvalidSearchQueryError.new( "[#{relation}] is not a valid relational operator" )
    end

    case field
    when "d"
      enforceRelational( ["=", "!="], relation, field )
      if relation == "="
        return " tickets.description LIKE #{param( "%" + likeEscape(value) + "%" )} ESCAPE '\\' "
      elsif relation == "!="
        return " tickets.description NOT LIKE #{param( "%" + likeEscape(value) + "%" )} ESCAPE '\\' "
      end
    when "a"
      enforceRelational( ["=", "!="], relation, field )
      return assignmentSubQuery( relation, value )
    when "l"
      enforceRelational( ["=", "!="], relation, field )
      return listeningSubQuery( relation, value )
    when "k"
      enforceRelational( ["=", "!="], relation, field )
      return keywordSubQuery( relation, value )
    when "j"
      enforceRelational( ["=", "!="], relation, field )
      return " tickets.project #{relation} #{param( projectToId( value ) )} " 
    when "s"
      enforceRelational( ["=", "!="], relation, field )
      return " tickets.status #{relation} #{param( statusToId( value ) )} "
    when "p"
      return " tickets.priority #{relation} #{param( value.to_i )} "
    when "h"
      return " tickets.total_minutes #{relation} #{param( value.to_f * 60 )} "
    when "r"
      return " tickets.minutes_remaining #{relation} #{param( value.to_f * 60 )} "
    else
      raise InvalidSearchQueryError.new( "[#{field}] is not a valid search field" )
    end
  end

  def enforceRelational( allowed, relation, field )
    unless allowed.include? relation
      raise InvalidSearchQueryError.new( "[#{relation}] is not supported for [#{field}]" )
    end
  end

  # Assign 'value' to a new prepared statement placeholder, and return the 
  # placeholder name (with the ':' prefix).
  def param( value )
    @paramNum += 1
    @params[@paramNum.to_s] = value
    return ":" + @paramNum.to_s
  end

  # Escape a string for SQL LIKE. Assumes the ESCAPE char is '\'
  def likeEscape( str )
    str.gsub( "\\", "\\\\" ).gsub( "%", "\%" ).gsub( "_", "\_" )
  end

  # Only de-slashes \" and \\
  def deslash( str )
    str.gsub( '\\"', '"' ).gsub( "\\\\", "\\" )
  end

  # NOTE: the 'user' field of assignments and listening must have COLLATE NOCASE
  # in order to make the comparison case insensitive.

  def assignmentSubQuery( relation, user )
    " 0 < (
    SELECT COUNT(ticket_id) FROM assignments
      WHERE assignments.user #{relation} #{param( user )}
      AND assignments.ticket_id = tickets.id LIMIT 1 ) "
  end

  def listeningSubQuery( relation, user )
    " 0 < (
    SELECT COUNT(ticket_id) FROM listening
      WHERE listening.user #{relation} #{param( user )}
      AND listening.ticket_id = tickets.id LIMIT 1 ) "
  end

  def keywordSubQuery( relation, keyword )
    id = listItemToId( Keyword, keyword )
    " 0 < (
    SELECT COUNT(ticket_id) FROM keyword_assoc
      WHERE keyword_assoc.keyword #{relation} #{param( id )}
      AND keyword_assoc.ticket_id = tickets.id LIMIT 1 ) "
  end

  def projectToId( project )
    listItemToId( Project, project )
  end

  def statusToId( status )
    listItemToId( Status, status )
  end

  def listItemToId( klass, search )
    klass.allItems.each do |item|
      if item.shortName.downcase == search.downcase
        return item.id
      end
    end
    raise InvalidSearchQueryError.new( "#{klass} [#{search}] not found" )
  end

end
