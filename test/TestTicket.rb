require 'fileutils'
require 'tickets/Ticket.rb'
require 'tickets/TicketChange.rb'
require 'tickets/Project.rb'
require 'tickets/Status.rb'

module Test
  class TestTicket < MiniTest::Unit::TestCase

    # TODO: test invalid attributes, like ticket ids that don't exist,
    # negative priorities, etc
    # TODO: test deleting a ticket with keyword, assigned, entries etc (foriegn key constraint)

    def testAttachFile
      ticket = Ticket.createNew

      file1 = String.randId
      file2 = String.randId

      File.write( "/tmp/#{file1}.txt", file1 )
      File.write( "/tmp/#{file2}.txt", file2 )

      ticket.attachFile( "/tmp/#{file1}.txt" )
      ticket.attachFile( "/tmp/#{file2}.txt" )

      assert_equal(
        ticket.attachedFileList.sort,
        [
          "#{file1}.txt",
          "#{file2}.txt"
        ].sort
      )

      modified = String.randId
      File.write( "/tmp/#{file1}.txt", modified )

      ticket.attachFile( "/tmp/#{file1}.txt" )

      attached = ticket.attachedFileList
      assert_includes( attached, "#{file1}.txt" )
      assert_includes( attached, "#{file2}.txt" )
      assert_equal( 3, attached.length )
      assert_match(
        /#{file1} \(\d{4}-\d\d-\d\d \d\d-\d\d-\d\d\)\.txt/,
        (newFile1 = (attached - ["#{file1}.txt", "#{file2}.txt"])[0])
      )

      destDir = "/tmp/" + String.randId
      FileUtils.mkdir( destDir )
      path = ticket.getAttachedFile( "#{file2}.txt", destDir )
      assert_equal( File.join( destDir, "#{file2}.txt" ), path )
      assert_equal( file2, File.read( path ) )

      secondPath = ticket.getAttachedFile( "#{file2}.txt", destDir )
      thirdPath = ticket.getAttachedFile( "#{file2}.txt", destDir )
      assert_equal( path + ".1", secondPath )
      assert_equal( path + ".2", thirdPath )

      path = ticket.getAttachedFile( "#{file1}.txt", destDir )
      assert_equal( file1, File.read( path ) )
      path = ticket.getAttachedFile( newFile1, destDir )
      assert_equal( modified, File.read( path ) )

      FileUtils.rm( "/tmp/#{file1}.txt" )
      FileUtils.rm( "/tmp/#{file2}.txt" )
    end

    def testCreateAndDeleteTicket
      ticket = Ticket.createNew
      assert_match( Ticket::TicketIdRegexp, ticket.id, "Bad ticket ID" )
      assert( ticket.exists?, "Ticket just created does not exist" )

      id = ticket.id
      ticket.delete
      refute( ticket.exists?, "Ticket just deleted exists" )

      assert_raises( Ticket::NoSuchTicketError ) do
        ticket = Ticket.new( id )
      end
    end

    def testUseTicketAfterDeleted
      ticket = Ticket.createNew
      ticket.delete

      getters = [
        :id, :description, :priority, :project, :status, :minutesSpent,
        :minutesRemaining, :assignedUsers, :listeningUsers, :dependencies,
        :dependers, :entries,
      ]

      oneArg = [
        :description=, :priority=, :project=, :status=, :minutesSpent=,
        :minutesRemaining=, :assignedUsers=, :assignTo, :assignedTo?,
        :unassign, :listeningUsers=, :dependencies=, :dependers=,
      ]

      getters.each do |method|
        assert_raises( Ticket::NoSuchTicketError ) do
          ticket.send( method )
        end
      end

      oneArg.each do |method|
        assert_raises( Ticket::NoSuchTicketError ) do
          ticket.send( method, nil )
        end
      end
    end

    def testChangeStandardAttributes
      existingTicketIdOne = Ticket.createNew.id
      existingTicketIdTwo = Ticket.createNew.id

      standardAttrs = [
        { :method => :description, :set => String.randId },
        { :method => :priority, :set => rand( 1000 ) },
        { :method => :project, :set => Project.allItems[0] },
        { :method => :project, :set => Project.allItems[1] },
        { :method => :status, :set => Status.allItems[0] },
        { :method => :status, :set => Status.allItems[1] },
        { :method => :minutesSpent, :set => rand( 1000 ) },
        { :method => :minutesRemaining, :set => rand( 1000 ) },
        { :method => :assignedUsers, :set => [String.randId, String.randId] },
        { :method => :listeningUsers, :set => [String.randId, String.randId] },
        { :method => :dependencies, :set => [existingTicketIdOne, existingTicketIdTwo] },
        { :method => :dependers, :set => [existingTicketIdOne, existingTicketIdTwo] },
      ].shuffle!

      ticket = Ticket.createNew

      standardAttrs.each do |attr|
        getter = attr[:method]
        setter = (getter.to_s + '=').to_sym
        value = attr[:set]

        ticket.send( setter, value )
        got = ticket.send( getter )

        # Order in an array doesn't matter
        if value.is_a? Array
          value.sort!
          got.sort!
        end

        assert_equal( value, got, "#{getter} returned a different value" )
      end
    end

    def testAssignment
      users = Array.new( 10 ) { String.randId }

      ticket = Ticket.createNew
      ticket.assignTo( users[0] )
      assert( ticket.assignedTo?( users[0] ), "assign to one user failed" )
      ticket.assignTo( users[1] )
      assert( ticket.assignedTo?( users[1] ), "assign to second user failed" )
      assert( ticket.assignedTo?( users[0] ), "first after assigning to second failed" )

      assert_equal( users[0..1].sort, ticket.assignedUsers.sort )

      # Make sure assigning someone twice doesn't duplicate the assignment
      3.times { ticket.assignTo( users[0] ) }
      3.times { ticket.assignTo( users[1] ) }
      3.times { ticket.assignedUsers += users[0..1] }

      assert_equal( users[0..1].sort, ticket.assignedUsers.sort )

      ticket.unassign( users[0] )
      refute( ticket.assignedTo?( users[0] ), "unassign to first failed" )
      assert( ticket.assignedTo?( users[1] ), "second shouldn't be unassigned" )
      ticket.unassign( users[1] )
      refute( ticket.assignedTo?( users[1] ), "unassign to second failed" )

      assert_equal( [], ticket.assignedUsers )
    end

    def testDuplicatesInList
      t1 = Ticket.createNew.id
      t2 = Ticket.createNew.id
      t3 = Ticket.createNew.id
      t4 = Ticket.createNew.id

      ticket = Ticket.createNew

      # Assignments
      ticket.assignedUsers = (["aUser", "anotherUser"] * 20).shuffle
      assert_equal( ["aUser", "anotherUser"].sort, ticket.assignedUsers.sort )

      # Listening users
      ticket.listeningUsers = (["aUser2", "anotherUser2"] * 20).shuffle
      assert_equal( ["aUser2", "anotherUser2"].sort, ticket.listeningUsers.sort )

      # Dependencies
      ticket.dependencies = ([t1, t2] * 20).shuffle
      assert_equal( [t1,t2].sort, ticket.dependencies.sort )

      # Depended on by
      ticket.dependers = ([t3, t4] * 20).shuffle
      assert_equal( [t3,t4].sort, ticket.dependers.sort )
    end

    def testDeleteCleanup
      dep1 = Ticket.createNew.id
      dep2 = Ticket.createNew.id
      assigned = String.randId
      listening = String.randId

      ticket = Ticket.createNew
      id = ticket.id
      ticket.description = "test"
      ticket.dependencies = [dep1]
      ticket.dependers = [dep2]
      ticket.assignTo( assigned )
      ticket.listeningUsers = [listening]

      change = TicketChange.new
      change[:changelog] = "A TEST CHANGELOG"
      change[:description] = "A TEST DESCRIPTION"
      change[:priority] = 31337
      change[:project] = Project.allItems[0]
      change[:status] = Status.allItems[0]
      change[:assignedUsers] = ["foobar"]
      ticket.commitChange( change, "test case" )

      ticket.delete

      assert_empty(
        Database::DB.execute(
          "SELECT * FROM tickets WHERE id = :id",
          :id => id
        )
      )

      ['assignments', 'listening', 'entries'].each do |table|
        assert_empty(
          Database::DB.execute(
            "SELECT * FROM #{table} WHERE ticket_id = :id",
            :id => id
          ),
          "Ticket data found in #{table} table"
        )
      end

      assert_empty(
        Database::DB.execute(
          "SELECT * FROM dependencies WHERE master = :id OR slave = :id",
          :id => id
        ),
        "Dependencies were not deleted"
      )
    end

  end
end
