#!/usr/bin/env ruby
$LOAD_PATH.unshift( File.dirname( __FILE__ ) )

require 'tickets/TicketSearch.rb'
require 'tickets/Ticket.rb'
require 'ui/CLIMenu.rb'
require 'ui/TicketCreator.rb'
require 'ui/TicketEditor.rb'
require 'ui/TicketViewer.rb'

# Don't try to read/write from argument file (it's a search query)
$stdin = STDIN
$stdout = STDOUT

trap( "SIGINT" ) do
  puts
  exit!
end

def homeScreen
  loop do
    menu = CLIMenu.new
    menu.add( :search, 'Search for a ticket', true )
    menu.add( :create, 'Create a new ticket' )
    choice = menu.show
    case choice
    when :search
      begin
        query = CLIMenu.prompt( "Query:" )
      end until searchForTickets( query )
    when :create
      TicketCreator.new.runUI
    when nil
      break
    end
  end
end

def searchForTickets( query )
  position = 0
  loop do
    search = TicketSearch.new( query )
    tickets = search.runSearch

    menu = CLIMenu.new
    menu.header = "Tickets matching [#{query}]:"
    tickets.each do |ticket|
      menu.add( ticket, ticket )
    end
    menu.addPersistent( :create, 'Create a new ticket', true )

    menu.position = position
    choice = menu.show
    position = menu.position

    case choice
    when Ticket
      TicketViewer.new( choice ).runUI
    when :create
      TicketCreator.new.runUI
    when nil
      break
    end
  end
  return true

rescue TicketSearch::InvalidSearchQueryError => e
  puts "INVALID QUERY: #{e.message}"
  return false
end

if ARGV.length == 0
  homeScreen
else
  searchForTickets( ARGV.join( ' ' ) )
end
