require 'tickets/TicketSearch.rb'
require 'tickets/Project.rb'
require 'tickets/Status.rb'
require 'tickets/Keyword.rb'

module Test
  class TestSearch < MiniTest::Unit::TestCase
    ###########################################################################
    #                      TEST VALID SEARCH QUERIES                          #
    ###########################################################################

    # TODO: for all the "partial match" things, test that they really partially match, esp desc.
    # TODO: make sure all of teh = <=, != work
    # TODO: extensive testing of double quote strings
    # TODO: be sure to test using > = < etc with text fields
    # TODO: ensure results are CACHED until the next runSearch
    # TODO: ensure assigned and listening DO NOT allow 'partial searches'
    # TODO: case-insensitivity tests
    # TODO: test trying to use wrong relational operators

    AllCreatedTickets = []

    def testTicketNumber
      t1 = Ticket.createNew
      t2 = Ticket.createNew
      twoTicketTest( t1, t2, t1.id, t2.id )
    end

    def testDescription
      t1 = Ticket.createNew
      t2 = Ticket.createNew
      t1.description = String.randId * 5
      t2.description = String.randId * 5
      twoTicketTest( t1, t2, "d=" + t1.description, "d=" + t2.description )
      twoTicketTest( t1, t2, 'd="' + t1.description + '"', 'd="' + t2.description + '"' )
      # partial matching
      twoTicketTest( t1, t2, 'd="' + t1.description[0,10] + '"', 'd="' + t2.description[0,10] + '"' )

      notSearch = searchFor( "d!=" + t1.description )
      refute_equal( 0, notSearch.length )
      refute_contains_ticket( t1, notSearch )
    end

    def testAssigned
      t1 = Ticket.createNew
      t2 = Ticket.createNew
      a1 = String.randId
      t1.assignedUsers = [a1]
      a2 = String.randId
      t2.assignedUsers = [a2]
      twoTicketTest( t1, t2, "a=" + a1, "a=" + a2 )
      twoTicketTest( t1, t2, "a=" + a1.upcase, "a=" + a2.downcase )

      t3 = Ticket.createNew
      t3.assignedUsers = [a1, a2]
      justT3 = searchFor( "a=#{a1} a=#{a2}" )
      assert_equal( 1, justT3.length )
      assert_contains_ticket( t3, justT3 )
    end

    def testListening
      t1 = Ticket.createNew
      t2 = Ticket.createNew
      a1 = String.randId
      t1.listeningUsers = [a1]
      a2 = String.randId
      t2.listeningUsers = [a2]
      twoTicketTest( t1, t2, "l=" + a1, "l=" + a2 )
      twoTicketTest( t1, t2, "l=" + a1.upcase, "l=" + a2.downcase )

      t3 = Ticket.createNew
      t3.listeningUsers = [a1, a2]
      justT3 = searchFor( "l=#{a1} l=#{a2}" )
      assert_equal( 1, justT3.length )
      assert_contains_ticket( t3, justT3 )
    end

    def testProject
      t1 = Ticket.createNew
      t1.project = Project.allItems[0]

      searchFor( "j=#{t1.project.shortName}" ).each do |ticket|
        assert_equal( t1.project, ticket.project )
      end
    end

    def testStatus
      t1 = Ticket.createNew
      t1.status = Status.allItems[0]

      searchFor( "s=#{t1.status.shortName}" ).each do |ticket|
        assert_equal( t1.status, ticket.status )
      end
    end

    def testPriority
      tLow = Ticket.createNew
      tMid = Ticket.createNew
      tHigh = Ticket.createNew

      tLow.priority = 0
      tMid.priority = 500
      tHigh.priority = 1000

      results = searchFor( "p=0 AND (#{tLow.id} OR #{tMid.id} OR #{tHigh.id})" )
      assert_contains_ticket( tLow, results )
      refute_contains_ticket( tMid, results )
      refute_contains_ticket( tHigh, results )

      results = searchFor( "p>0 AND (#{tLow.id} OR #{tMid.id} OR #{tHigh.id})" )
      refute_contains_ticket( tLow, results )
      assert_contains_ticket( tMid, results )
      assert_contains_ticket( tHigh, results )

      results = searchFor( "p>=0 AND (#{tLow.id} OR #{tMid.id} OR #{tHigh.id})" )
      assert_contains_ticket( tLow, results )
      assert_contains_ticket( tMid, results )
      assert_contains_ticket( tHigh, results )

      results = searchFor( "p>=300 AND p<=600 AND (#{tLow.id} OR #{tMid.id} OR #{tHigh.id})" )
      refute_contains_ticket( tLow, results )
      assert_contains_ticket( tMid, results )
      refute_contains_ticket( tHigh, results )

      results = searchFor( "p!=500 AND (#{tLow.id} OR #{tMid.id} OR #{tHigh.id})" )
      assert_contains_ticket( tLow, results )
      refute_contains_ticket( tMid, results )
      assert_contains_ticket( tHigh, results )
    end

    def testKeyword
      t1 = Ticket.createNew
      t1.keywords = Keyword.allItems

      query = Keyword.allItems.map { |k| "k=#{k.shortName}" }.join( " AND " )
      searchFor( query ).each do |ticket|
        assert_equal( ticket.keywords.sort, Keyword.allItems.sort )
      end
    end

    def testCrazyExpression
      # TODO: Test some crazy shit with brackets
    end

    def testFieldCombinations
      # TODO: test pairs of fields
    end

    def assert_contains_ticket( expectedTicketId, searchResults, msg = '' )
      expectedTicketId = expectedTicketId.id if expectedTicketId.is_a? Ticket
      justIds = searchResults.map { |r| r.id }
      assert_includes( justIds, expectedTicketId, msg )
    end

    def refute_contains_ticket( expectedTicketId, searchResults, msg = '' )
      expectedTicketId = expectedTicketId.id if expectedTicketId.is_a? Ticket
      justIds = searchResults.map { |r| r.id }
      refute_includes( justIds, expectedTicketId, msg )
    end

    def searchFor( query )
      TicketSearch.new( query ).runSearch
    end

    def twoTicketTest( t1, t2, c1, c2 )
      assert_empty( searchFor( "#{c1} #{c2}" ) )
      assert_empty( searchFor( "#{c1} AND #{c2}" ) )

      justT1 = searchFor( c1 )
      assert_equal( 1, justT1.length )
      assert_contains_ticket( t1, justT1 )

      justT2 = searchFor( c2 )
      assert_equal( 1, justT2.length )
      assert_contains_ticket( t2, justT2 )

      # NOTE: The closing braces ')' must be separated from the condition by
      # at least one space. If not, they'll become part of a non-quoted condition.

      [t1,t2].each do |ticket|
        assert_contains_ticket( ticket, searchFor( "#{c1} OR #{c2}" ) )
        assert_contains_ticket( ticket, searchFor( "( #{c1} ) OR ( #{c2} )" ) )
        assert_contains_ticket( ticket, searchFor( "(#{c1} OR #{c2} ) OR #{c2}" ) )
      end

      justT1 = searchFor( "( #{c1} OR #{c2} ) AND #{c1}" )
      assert_equal( 1, justT1.length )
      assert_contains_ticket( t1, justT1 )
      refute_contains_ticket( t2, justT1 )
    end


    ###########################################################################
    #                     TEST INVALID SEARCH QUERIES                         #
    ###########################################################################


    def testInvalidField
      assert_raises( TicketSearch::InvalidSearchQueryError ) do 
        # 'z' is not a valid search field
        TicketSearch.new( "z=blah" )
      end
    end

    def testBracketMismatch
      [
        ") d=foo",
        "( d=foo",
        "( d=foo (",
        "( d=foo )) OR ( d=bar )",
        "( ( d=foo ) OR ( d = bar )",
      ].each do |bad|
        assert_raises( TicketSearch::InvalidSearchQueryError, bad ) do
          TicketSearch.new( bad ).runSearch
        end
      end
    end

    def testBooleanMismatch
      [
        "d=foo AND",
        "d=foo OR",
        "d=foo AND OR d=foo",
        "( d=foo OR ) d=foo",
        "( d = foo ) OR d=foo",
      ].each do |bad|
        assert_raises( TicketSearch::InvalidSearchQueryError, bad ) do
          TicketSearch.new( bad ).runSearch
        end
      end
    end

    def testInvalidCondition
      assert_raises( TicketSearch::InvalidSearchQueryError ) do
        TicketSearch.new( "j#foo" ).runSearch
      end
    end

    def testJunkBetweenPrimitives
      assert_raises( TicketSearch::InvalidSearchQueryError ) do
        TicketSearch.new( "d=foo abcdef d=bar" ).runSearch
      end
    end

    def testTrailingJunk
      assert_raises( TicketSearch::InvalidSearchQueryError ) do
        TicketSearch.new( "d=foo abcdef" ).runSearch
      end
    end

    def testLeadingJunk
      assert_raises( TicketSearch::InvalidSearchQueryError ) do
        TicketSearch.new( "abcdef d=foo" ).runSearch
      end
    end

    def testMissingKeyword
      assert_raises( TicketSearch::InvalidSearchQueryError ) do 
        TicketSearch.new( "k=IdoNotExistIdoNot" ).runSearch
      end
    end

    def testMissingProject
      assert_raises( TicketSearch::InvalidSearchQueryError ) do 
        TicketSearch.new( "j=IdoNotExistIdoNot" ).runSearch
      end
    end

    def testMissingStatus
      assert_raises( TicketSearch::InvalidSearchQueryError ) do 
        TicketSearch.new( "s=IdoNotExistIdoNot" ).runSearch
      end
    end

    def testMissingValue
      [
        "d=",
        "d=foo OR d=",
        "d=foo OR d= OR d=foo",
      ].each do |bad|
        assert_raises( TicketSearch::InvalidSearchQueryError, bad ) do
          TicketSearch.new( bad ).runSearch
        end
      end

      # If the user really wants to search the empty string, they must use quotes
      [
        'd=""',
        'd=foo OR d=""',
        'd=foo OR d="" OR d=foo',
      ].each do |good|
          TicketSearch.new( good ).runSearch
      end
    end

  end
end
