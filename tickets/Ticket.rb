require 'fileutils'
require 'core/Database.rb'
require 'tickets/TicketEntry.rb'
require 'tickets/NewTicketEntry.rb'
require 'tickets/Project.rb'
require 'tickets/Status.rb'
require 'tickets/Keyword.rb'
require 'core/Mail.rb'
require 'core/Settings.rb'
require 'filters/EmailFilter.rb'
require 'core/User.rb'

class Ticket

  class NoSuchTicketError < StandardError; end

  TicketIdRegexp = /\d{6}-\d{3}/
  ChangeLogIndentation = 4

  #############################################################################
  # ============================ STATIC METHODS ============================= #
  #############################################################################

  def self.createNew
    id = self.nextTicketId
    Database::DB.execute(
      "INSERT INTO tickets (id, description, priority) VALUES( :id, :desc, :priority )",
      :id => id,
      :desc => "NO DESCRIPTION",
      :priority => 0,
    )
    return Ticket.new( id )
  end

  def self.ticketExists?( id )
    Ticket.new( id )
    return true
  rescue NoSuchTicketError
    return false
  end


  #############################################################################
  #############################################################################

  def initialize( id )
    @id = id
    unless exists?
      raise NoSuchTicketError.new( "Ticket with id [#{id}] does not exist." )
    end
  end

  def exists?
    res = Database::DB.execute(
      "SELECT id FROM tickets WHERE id = :id",
      :id => @id,
    )
    !res.empty?
  end

  def delete
    must_exist

    # Delete the associated data. Must be done first because of the foreign keys.
    ['assignments', 'listening', 'entries', 'keyword_assoc'].each do |table|
      Database::DB.execute(
        "DELETE FROM #{table} WHERE ticket_id = :id",
        :id => @id,
      )
    end
    Database::DB.execute(
      "DELETE FROM dependencies WHERE master = :id OR slave = :id",
      :id => @id,
    )

    # Delete the main ticket row
    Database::DB.execute(
      "DELETE FROM tickets WHERE id = :id",
      :id => @id,
    )
  end

  # Makes a change specified by a TicketChange object.
  def commitChange( change, user = User.getlogin )
    must_exist

    change[:minutesSpent] = 0 if change[:minutesSpent].nil?

    # Normalize dependencies to an array of ticket ids.
    modifications = {}
    [:dependencies, :dependers].each do |depType|
      if change.key? depType
        modifications[depType] = change[depType].map do |dep|
          dep.is_a?( Ticket ) ? dep.id : dep
        end
      end
    end

    # Make sure the change will succeed before committing, so we don't 
    # half-commit a change then fail.
    ensureChangeIsConsistent( change.merge( modifications ) )

    changes = ""

    # Process everything except the change log.
    change.each do |id, value|
      if modifications.key? id
        value = modifications[id]
      end

      case id
      when :project
        changes += diff( 'Project', self.project, value )
        self.project = value
      when :status
        changes += diff( 'Status', self.status, value )
        self.status = value
      when :keywords
        changes += diff( 'Keywords', self.keywords, value)
        self.keywords = value
      when :description
        changes += diff( 'Description', self.description, description )
        self.description = value
      when :assignedUsers
        changes += diff( 'Assigned', self.assignedUsers, value )
        self.assignedUsers = value
      when :listeningUsers
        changes += diff( 'Listening', self.listeningUsers, value )
        self.listeningUsers = value
      when :priority
        changes += diff( 'Priority', self.priority, value )
        self.priority = value
      when :minutesSpent
        self.minutesSpent += value
      when :minutesRemaining
        self.minutesRemaining = value
      when :dependencies
        changes += diff( 'Depends', self.dependencies, value )
        self.dependencies = value
      when :dependers
        changes += diff( 'Depended on by', self.dependers, value )
        self.dependers = value
      when :due
        changes += diff( 'Due date', self.due, value )
        self.due = value
      end
    end

    if changes.empty?
      changelog = change[:changelog]
    else
      changelog = changes + "\n" + change[:changelog]
    end

    # Add the change log entry
    cl = NewTicketEntry.new( @id )
    cl.user = user
    cl.text = changelog
    cl.minutes = change[:minutesSpent]
    cl.commit

    toAlert = self.listeningUsers | self.assignedUsers

    toAlert.each do |username|
      mail = Mail.new
      mail.to = EmailFilter.filter( username )
      mail.subject = "#{self.project.shortName}: #{self.description} (#{@id})"
      mail.message = headers + "\n\n" + "-"*80 + "\n" + getChangeLogAsString
      mail.send
    end
  end

  def ensureChangeIsConsistent( change )
    if change[:changelog].nil? or change[:changelog].strip.empty?
      raise TicketChange::InvalidAttributeError.new( "Please provide a changelog entry." )
    end

    if change[:description].nil? or change[:description].strip.empty?
      raise TicketChange::InvalidAttributeError.new( "Please provide a description." )
    end

    if change[:priority].nil? or change[:priority] < 0
      raise TicketChange::InvalidAttributeError.new( "Please provide a priority >= 0." )
    end

    if change[:project].nil?
      raise TicketChange::InvalidAttributeError.new( "Please specify a project." )
    end

    if change[:status].nil?
      raise TicketChange::InvalidAttributeError.new( "Please specify a status." )
    end

    if change[:assignedUsers].nil? or change[:assignedUsers].empty?
      raise TicketChange::InvalidAttributeError.new( "Please assign at least one user." )
    end

    unless change[:dependencies].nil?
      change[:dependencies].each do |dep|
        unless Ticket.ticketExists? dep
          raise TicketChange::InvalidAttributeError.new( "Ticket [#{dep}] does not exist." )
        end
      end
    end

    unless change[:dependers].nil?
      change[:dependers].each do |dep|
        unless Ticket.ticketExists? dep
          raise TicketChange::InvalidAttributeError.new( "Ticket [#{dep}] does not exist." )
        end
      end
    end

    unless change[:due] == false or change[:due].is_a? Time
      raise TicketChange::InvalidAttributeError.new( "Due date is not a Time object." )
    end
  end
  private :ensureChangeIsConsistent

  def to_s
    longestProject = Project.allItems.map { |p| p.shortName.length }.max
    longestStatus = Status.allItems.map { |s| s.shortName.length }.max
    project = self.project.shortName.center( longestProject )
    status = self.status.shortName.center( longestStatus )
    priority = self.priority.to_s.center( 6 )
    due = self.due ? "{" + self.dueStringShort + "}" : ""
    "#{self.id} | #{priority} | #{project} | #{status} | #{self.description} #{due}"
  rescue
    "<<<<< BROKEN >>>>>"
  end

  def showChangeLog( withHeaders = false )
    pager = ENV['TIX_PAGER'] || ENV['PAGER'] || 'less'
    IO.popen( pager, "w" ) do |pg|
      pg.print headers + "\n\n" + "-"*80 + "\n" + getChangeLogAsString
    end
  end

  def getChangeLogAsString
    log = ""
    self.entries.each do |entry|
      log << entry.time.strftime( Settings::LONG_TIME_FORMAT ) << "\n" <<
        entry.user << " (#{(entry.minutes / 60.0).round( 2 )}): \n\n" << 
        entry.text.gsub( /^/, ' ' * ChangeLogIndentation ) << "\n\n" << "-" * 80 << "\n"
    end
    return log
  end

  def headers
    headers = [
      ["ID:", self.id],
      ["Description:", self.description],
      ["Project:", self.project],
      ["Status:", self.status],
      ["Assigned users:", self.assignedUsers],
      ["Listening users:", self.listeningUsers],
      ["Priority:", self.priority],
      ["Hours spent:", (self.minutesSpent.to_f / 60).round( 2 )],
      ["Hours remaining:", (self.minutesRemaining.to_f / 60).round( 2 )],
      ["Keywords:", self.keywords.map { |k| k.shortName }],
      ["Dependencies:", self.dependencies],
      ["Depended on by:", self.dependers],
      ["Due date:", self.dueStringLong],
    ]
    length = 0
    headers.each do |header|
      length = header[0].length if header[0].length > length
    end

    headers.map { |header|
      "%#{length}s  %s" % header
    }.join( "\n" )
  end

  def attachFile( filePath, user = User.getlogin )
    createBaseDir()

    # Create a folder for this ticket if it doesn't already exist.
    base = File.join( Settings::ATTACHED_FILES_DIR, @id )
    unless File.directory? base
      FileUtils.mkdir( base )
    end

    moveTo = File.join( base, File.basename( filePath ) )
    if File.exists? moveTo
      name = File.basename( filePath, '.*' )
      name = name +
        " (" + Time.now.strftime( "%Y-%m-%d %H-%M-%S" ) + ")" +
        File.extname( filePath )
      moveTo = File.join( base, name )
    end

    FileUtils.cp( filePath, moveTo )
    FileUtils.chmod( 0444, moveTo ) # Let everyone read it.

    # Add the change log entry
    cl = NewTicketEntry.new( @id )
    cl.user = user
    cl.text = "Attached file: #{File.basename( moveTo )}"
    cl.minutes = 0
    cl.commit
  end

  def attachedFileList
    createBaseDir()

    base = File.join( Settings::ATTACHED_FILES_DIR, @id )
    return Dir.foreach( base ).to_a - [".", ".."]
  end

  def getAttachedFile( name, destDir )
    createBaseDir()

    path = File.join( Settings::ATTACHED_FILES_DIR, @id, name )
    dest = File.join( destDir, name )

    # Don't overwrite an existing file.
    i = 1
    while File.exists? dest
      dest = File.join( destDir, name + "." + i.to_s )
      i += 1
    end

    FileUtils.cp( path, dest )
    return dest
  end

  def createBaseDir
    base = File.join( Settings::ATTACHED_FILES_DIR, @id )
    unless File.directory? base
      FileUtils.mkdir base
    end
  end

  #############################################################################
  # ================= TICKET ATTRIBUTE GETTERS AND SETTERS ================== #
  #############################################################################

  def id
    must_exist
    getColumn( 'id' )
  end

  def description
    must_exist
    getColumn( 'description' )
  end

  def description=( newDesc )
    must_exist
    setColumn( 'description', newDesc )
  end

  def priority
    must_exist
    getColumn( 'priority' )
  end

  def priority=( newPriority )
    must_exist
    setColumn( 'priority', newPriority )
  end

  def project
    must_exist
    Project.fromId( getColumn( 'project' ) )
  rescue Project::NoSuchListItemError
    nil
  end

  def project=( projectObj )
    must_exist
    setColumn( 'project', projectObj.id )
  end

  def status
    must_exist
    Status.fromId( getColumn( 'status' ) )
  rescue Status::NoSuchListItemError
    nil
  end

  def status=( statusObj )
    must_exist
    setColumn( 'status', statusObj.id )
  end

  # Set the due date from either an UNIX timestamp or a Time object.
  # Pass false to remove the due date.
  def due=( time )
    if time == false
      setColumn( 'due', 0 )
    else
      time = Time.at( time ) unless time.is_a? Time
      setColumn( 'due', time.to_i )
    end
  end

  # Returns the due date as Time object, or false if there is no due date.
  def due
    time = getColumn( 'due' )
    if( time == 0 )
      return false
    else
      return Time.at( getColumn( 'due' ) )
    end
  end

  def dueStringShort
    return "" unless self.due
    self.due.strftime( Settings::SHORT_TIME_FORMAT )
  end

  def dueStringLong
    return "" unless self.due
    self.due.strftime( Settings::LONG_TIME_FORMAT )
  end
  
  def minutesSpent
    must_exist
    getColumn( 'total_minutes' )
  end

  def minutesSpent=( totalMinsSpent )
    must_exist
    setColumn( 'total_minutes', totalMinsSpent )
  end

  def minutesRemaining
    must_exist
    getColumn( 'minutes_remaining' )
  end

  def minutesRemaining=( totalMinutesRemaining )
    must_exist
    setColumn( 'minutes_remaining', totalMinutesRemaining )
  end

  def keywords
    must_exist
    Database::DB.execute( 
      "SELECT keyword FROM keyword_assoc WHERE ticket_id = :ticket_id",
      :ticket_id => @id
    ).map do |row|
      begin
        Keyword.fromId( row['keyword'] )
      rescue Keyword::NoSuchTicketError
        nil
      end
    end.reject { |kw| kw.nil? }
  end

  def keywords=( keywords )
    must_exist
    keywords = keywords.uniq

    Database::DB.execute(
      "DELETE FROM keyword_assoc WHERE ticket_id = :id",
      :id => @id
    )
    
    keywords.each do |keyword|
      Database::DB.execute(
        "INSERT INTO keyword_assoc (ticket_id, keyword)
          VALUES (:id, :keyword)",
        :id => @id,
        :keyword => keyword.id
      )
    end
  end

  def assignedUsers=( users )
    must_exist
    users = users.uniq

    Database::DB.execute(
      "DELETE FROM assignments WHERE ticket_id = :id",
      :id => @id
    )

    users.each do |user|
      Database::DB.execute(
        "INSERT INTO assignments (ticket_id, user)
          VALUES (:id, :user)",
        :id => @id,
        :user => user
      )
    end
  end

  def assignedUsers
    must_exist
    Database::DB.execute( 
      "SELECT user FROM assignments WHERE ticket_id = :ticket_id",
      :ticket_id => @id
    ).map { |row| row['user'] }
  end

  def assignTo( user )
    must_exist
    unless assignedTo? user
      Database::DB.execute(
        "INSERT INTO assignments (ticket_id, user) VALUES(:ticket_id, :user)",
        :ticket_id => @id,
        :user => user
      )
    end
  end

  def assignedTo?( user )
    must_exist
    not Database::DB.execute(
      "SELECT ticket_id FROM assignments WHERE ticket_id = :ticket_id AND user = :user",
      :ticket_id => @id,
      :user => user
    ).empty?
  end

  def unassign( user )
    must_exist
    Database::DB.execute(
      "DELETE FROM assignments WHERE ticket_id = :ticket_id AND user = :user",
      :ticket_id => @id,
      :user => user
    )
  end

  def listeningUsers=( users )
    must_exist
    users = users.uniq

    Database::DB.execute(
      "DELETE FROM listening WHERE ticket_id = :id",
      :id => @id
    )

    users.each do |user|
      Database::DB.execute(
        "INSERT INTO listening (ticket_id, user)
          VALUES (:id, :user)",
        :id => @id,
        :user => user
      )
    end
  end

  def listeningUsers
    must_exist
    Database::DB.execute( 
      "SELECT user FROM listening WHERE ticket_id = :ticket_id",
      :ticket_id => @id
    ).map { |row| row['user'] }
  end

  # TODO: change all of the = to be more efficient and return the differences
  def dependencies=( listOfTicketIds )
    must_exist
    listOfTicketIds = listOfTicketIds.uniq

    Database::DB.execute(
      "DELETE FROM dependencies WHERE master = :id",
      :id => @id
    )

    listOfTicketIds.each do |dep|
      Ticket.new( dep ) # raises if the ticket doesn't exist
      Database::DB.execute(
        "INSERT INTO dependencies (master, slave)
          VALUES (:master, :slave)",
        :master => @id,
        :slave => dep
      )
    end
  end

  def dependencies
    must_exist
    Database::DB.execute(
      "SELECT slave FROM dependencies WHERE master = :id",
      :id => @id
    ).map { |row| row['slave'] }
  end

  # TODO: these can easily take an array of tickets OR ticket ids
  def dependers=( listOfDependers )
    must_exist
    listOfDependers = listOfDependers.uniq

    Database::DB.execute(
      "DELETE FROM dependencies WHERE slave = :id",
      :id => @id,
    )

    listOfDependers.each do |dep|
      Ticket.new( dep ) # raises if the ticket doesn't exist
      Database::DB.execute(
        "INSERT INTO dependencies (master, slave)
          VALUES (:master, :slave)",
        :master => dep,
        :slave => @id,
      )
    end
  end

  def dependers
    must_exist
    Database::DB.execute(
      "SELECT master FROM dependencies WHERE slave = :id",
      :id => @id
    ).map { |row| row['master'] }
  end

  # Returns all ticket entries in reverse-chronological order
  def entries
    must_exist
    TicketEntry.getAllTicketEntries( @id )
  end

  #############################################################################
  # ============================ HELPER METHODS ============================= #
  #############################################################################

  private

  def getColumn( attr )
    raise 'Invalid column' unless isValidColumn? attr
    Database::DB.get_first_row(
      "SELECT #{attr} FROM tickets WHERE id = :id",
      :id => @id
    )[attr]
  end

  def setColumn( attr, value )
    raise 'Invalid column' unless isValidColumn? attr
    Database::DB.execute(
      "UPDATE tickets SET #{attr} = :value WHERE id = :id",
      :value => value,
      :id => @id
    )
  end

  def isValidColumn?( attr )
    ['id', 'description', 'priority', 'total_minutes',
     'minutes_remaining', 'status', 'project', 'due'].include? attr
  end

  def diff( desc, orig, changed )
    if orig.nil?
      if changed.is_a? Array
        orig = []
      else
        orig = ""
      end
    end

    if orig.is_a? Array
      orig = orig.sort
      changed = changed.sort
      return "" if orig == changed
      removed = (orig - changed).map { |x| "-#{shortToString( x )}" }.join( ', ' )
      added = (changed - orig).map { |x| "+#{shortToString( x )}" }.join( ', ' )
      removed += ", " unless removed.empty? 
      return desc + ": " + removed + added + "\n"
    else
      return "" if orig == changed
      return desc + ": #{shortToString( orig )} --> #{shortToString( changed )}\n"
    end
  end

  def shortToString( x )
    if x.kind_of? ListItem
      x.shortName
    elsif x.kind_of? Time
      x.strftime( Settings::LONG_TIME_FORMAT )
    else
      x ? x.to_s : ""
    end
  end

  def must_exist
    raise NoSuchTicketError.new( 'Ticket has been deleted.' ) unless exists?
  end

  def self.nextTicketId
    lastId = Database::DB.get_first_row(
      "SELECT last_id FROM config"
    )['last_id']

    lastDate = lastId[0,6] # Before the '-'
    lastN = lastId[7,3] # After the '-'

    t = Time.now
    thisDate = "%02s%02d%02d" % [t.year.to_s[2,2], t.month, t.day]

    thisN = (lastDate == thisDate) ? lastN.to_i + 1 : 0
    if thisN > 999
      raise 'Too many tickets created today'
    end
    thisId = "%s-%03d" % [thisDate, thisN] 

    Database::DB.execute(
      "UPDATE config SET last_id = :id",
      :id => thisId
    )

    return  thisId
  end

end
