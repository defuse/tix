require 'tickets/Ticket.rb'
require 'tickets/TicketChange.rb'
require 'tickets/Project.rb'
require 'tickets/Status.rb'

module Test
  class TestTicketChange < MiniTest::Unit::TestCase

    def testTicketChange

    end

    def testReverseChronologicalOrder

    end

    def testChangeLogRequired
      ticket = Ticket.createNew
      change = TicketChange.new

      # Set everything except the changelog
      change[:description] = "hello"
      change[:project] = Project.allItems[0]
      change[:status] = Status.allItems[0]
      change[:priority] = 1
      change[:minutesSpent] = 60
      change[:minutesRemaining] = 60
      change[:assignedUsers] = ["tester"]
      change[:listeningUsers] = ["tester"]

      assert_raises( TicketChange::InvalidAttributeError ) do
        ticket.commitChange( change, "tester" )
      end
    end

    def testInitialValuesRequired
    
    end

    def testFallbackOnCommitFailure
     #  ticket = Ticket.createNew
     #  change = TicketChange.new

     #  change[:changelog] = "hello"
    end

  end
end
