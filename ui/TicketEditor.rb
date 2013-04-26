require 'tickets/TicketChange.rb'
require 'tickets/TicketSearch.rb'
require 'tickets/Ticket.rb'
require 'ui/CLIMenu.rb'
require 'core/User.rb'
require 'core/Settings.rb'

class TicketEditor

  EditFileDirectory = "/tmp"

  # NOTE: This class must cope with ticket being nil, because TicketCreator
  # inherits using a nil ticket. The inheritance really should be the other 
  # way around, but oh well.
  def initialize( ticket )
    @ticket = ticket
    @flash = nil
  end

  def runUI
    change = TicketChange.new( @ticket )

    # TODO: get and reset position
    # TODO: actually show the list items, but only shortName
    position = 0
    loop do
      menu = CLIMenu.new
      menu.header = @ticket ? @ticket.headers : "New ticket:"

      longest = 0
      TicketChange::ChangeAttributes.each do |id, info|
        longest = info[:name].length if info[:name].length > longest
      end

      TicketChange::ChangeAttributes.each do |id, info|
        # :bigtext and :list are too big to show in-line
        display =
          case info[:type]
          when :bigtext
            ( change[id] && !change[id].empty? ) ? "assigned" : ""
          when :list
            ( change[id] && !change[id].empty? ) ? "assigned" : ""
          when :time
            if change[id]
              change[id].strftime( Settings::LONG_TIME_FORMAT )
            else
              ""
            end
          else
            # Minutes spent and minutes remaining are displayed as hours
            if id == :minutesSpent or id == :minutesRemaining
              (change[id] / 60.0).round( 2 )
            else
              change[id]
            end
          end
        name = info[:name] + "." * (longest - info[:name].length + 5)
        menu.add( id, "#{name}[#{display}]" )
      end

      menu.addPersistent( :commit, 'Commit', true )
      menu.addPersistent( :cancel, 'Cancel' )

      menu.position = position
      toChange = menu.show( @flash )
      position = menu.position
      @flash = nil
      info = TicketChange::ChangeAttributes[toChange]

      case toChange
      # Meta-items
      when nil, :cancel
        return
      when :commit
        return if commit( change )

      # Attribute special cases
      when :changelog
        change[toChange] = getChangeLogEntry( info[:name], change[toChange] )
        if change[toChange].nil?
          print "\n\n *** Invalid change log. Reverting. ***\n\n"
          # We don't need to do anything to revert it, since it is set to nil.
        end
      when :minutesSpent
        # We're actually asking for the hours spent as a float
        value = CLIMenu.prompt( info[:name] + ":" ) do |val|
          val =~ /\d+\.?\d*/
        end
        change[:minutesSpent] = (value.to_f * 60).ceil
        # Decrease remaining minutes, unless it has been set explicitly
        unless change.key? :minutesRemaining
          change[:minutesRemaining] = [change[:minutesRemaining] - change[:minutesSpent], 0].max
        end
      when :minutesRemaining
        # We're actually asking for the hours remaining as a float
        value = CLIMenu.prompt( info[:name] + ":" ) do |val|
          val =~ /\d+\.?\d*/
        end
        change[:minutesRemaining] = (value.to_f * 60).ceil
      when :dependencies, :dependers
        # Let the user search for a ticket and select it from a list.
        results = nil
        query = nil
        change[toChange] = CLIMenu.freeListEditor( info[:name] + ":", change[toChange] ) do
          query = CLIMenu.prompt( "Search query:" ) do |q|
            begin
              results = TicketSearch.new( q ).runSearch
              true
            rescue TicketSearch::InvalidSearchQueryError
              false
            end
          end

          unless results.nil? or results.empty?
            results = CLIMenu.checkboxMenu( 'select:', results, [], "Tickets matching '#{query}'" )
          end

          results
        end

      # Default attribute get/set behaviour
      else
        case info[:type]
        when :list
          if info[:allowed]
            change[toChange] = CLIMenu.checkboxMenu( info[:name] + ":", info[:allowed], change[toChange] )
          else
            change[toChange] = CLIMenu.freeListEditor( info[:name] + ":", change[toChange] )
          end
        when :int
          change[toChange] = getInteger( info[:name], info[:allowed], change[toChange] )
        when :text, :item
          change[toChange] = getSingleLine( info[:name], info[:allowed], change[toChange] )
        when :bigtext
          change[toChange] = getBigText( info[:name], change[toChange] )
        when :time
          gotGoodTimeString = false
          until gotGoodTimeString
            begin
              tStr = getSingleLine( info[:name], info[:allowed], change[toChange] )
              if tStr.upcase == "NONE"
                tStr = ""
              end
              change[toChange] = tStr
            rescue TicketChange::InvalidAttributeError
              puts " *** Not a valid time string. Specify \"none\" to remove the attribute. ***"
              next
            end
            gotGoodTimeString = true
          end
        end # case info[:type]
      end # case toChange

    end # loop
  end

  def commit( change )
    @ticket.commitChange( change, User.getlogin )
    return true
  rescue TicketChange::InvalidAttributeError => e
    @flash = "  ********* ERROR: #{e.message} *********"
    return false
  end

  def getInteger( name, allowed, current )
    if allowed
      return CLIMenu.radioButtonMenu( name + ":", allowed, current ).to_i
    else
      value = CLIMenu.prompt( name + ":" ) do |val|
        val =~ /\d+/
      end
      return value.to_i
    end
  end

  def getSingleLine( name, allowed, current )
    if allowed
      return CLIMenu.radioButtonMenu( name + ":", allowed, current )
    else
      res = CLIMenu.prompt( name + ":" )
      if res.empty? or res.downcase == 'q'
          res = current
      end
      return res
    end
  end

  def getBigText( name, current )
    editor = ENV['TIX_EDITOR'] || ENV['EDITOR'] || 'vi'
    fileName = File.join( EditFileDirectory, rand(2**64).to_s(36) + ".txt" )
    File.write( fileName, current )
    if ["vi", "vim", "gvim"].include? editor.downcase
      system(
        editor,
        # Force line wrapping, taking indentation into consideration.
        "-c", "set tw=#{80 - Ticket::ChangeLogIndentation - 1}",
        # Clear the file type, since Vim likes to think it's a UNIX conf file.
        "-c", "set ft=ticket",
        fileName
      )
    else
      system( editor, fileName )
    end
    result = File.read( fileName )
    File.unlink( fileName )
    return result
  end

  def getChangeLogEntry( name, current )
    separator = "--This line, and those below, will be ignored--\n" +
      " ** Indentation and the date will be added automatically. **\n\n"
    current ||= ""
    previousEntries = @ticket ? @ticket.getChangeLogAsString : ""
    show = current + "\n\n" +  separator + previousEntries
    edited = getBigText( name, show )
    eos = edited.index( separator )
    if eos
      entry = edited[0...eos].rstrip
      # Make sure the user actually entered some text
      if entry.strip.empty?
        return nil
      else 
        return entry
      end
    else # User messed with the separator
      return nil
    end
  end

end
