require 'time'
require 'tickets/Project.rb'
require 'tickets/Status.rb'
require 'tickets/Keyword.rb'
require 'core/User.rb'

class TicketChange < Hash

  class InvalidAttributeError < StandardError ; end

  DefaultPriority = 5000

  # Attribute types:
  #   :list - An unordered list of strings
  #   :item - A single item in a list (must provide :allowed)
  #   :text - A single-line string
  #   :bigtext - A multi-line string
  #   :int - An integer
  #   :time - A point in time (Time object)
  ChangeAttributes = {
    :description => { :name => 'Description', :type => :text, :allowed => nil },
    :project => { :name => 'Project', :type => :item, :allowed => Project.allItems },
    :status => { :name => 'Status', :type => :item, :allowed => Status.allItems },
    :keywords => { :name => 'Keywords', :type => :list, :allowed => Keyword.allItems },
    :changelog => { :name => 'Change log', :type => :bigtext, :allowed => nil },
    :assignedUsers => { :name => 'Assigned users', :type => :list, :allowed => nil },
    :listeningUsers => { :name => 'Listening users', :type => :list, :allowed => nil },
    :priority => { :name => 'Priority', :type => :int, :allowed => nil },
    # These are really "minutes spent" and "minutes remaining"
    :minutesSpent => { :name => 'Hours spent', :type => :int, :allowed => nil },
    :minutesRemaining => { :name => 'Hours remaining', :type => :int, :allowed => nil },
    :dependencies => { :name => 'Dependencies', :type => :list, :allowed => nil },
    :dependers => { :name => 'Depended on by', :type => :list, :allowed => nil },
    :due => { :name => 'Due date', :type => :time, :allowed => nil },
  }

  def initialize( ticket = nil )
    @ticket = ticket

    # Set default values if it's a new ticket
    if @ticket.nil?
      self[:minutesSpent] = 0
      self[:minutesRemaining] = 0
      self[:status] = Status.allItems[0]
      self[:priority] = DefaultPriority
      self[:assignedUsers] = [User.getlogin]
      self[:due] = ""
    end
  end

  # When given a real ticket, default to the ticket's actual values.
  # NOTE: This forces TicketChange#commitChange to iterate over key-value pairs
  # instead of do a lookup directly, else it would be needlessly changing 
  # attributes to their current values.
  def []( id )
    value = super( id )
    if value.nil? and @ticket
      # Map the id to one of Ticket's getters
      # TODO: we can just use send here (but not always -- be careful)
      value = 
        case id
        when :description
          @ticket.description
        when :project
          @ticket.project
        when :status
          @ticket.status
        when :keywords
          @ticket.keywords
        when :assignedUsers
          @ticket.assignedUsers
        when :listeningUsers
          @ticket.listeningUsers
        when :priority
          @ticket.priority
        when :minutesSpent
          0
        when :minutesRemaining
          @ticket.minutesRemaining
        when :dependencies
          @ticket.dependencies
        when :dependers
          @ticket.dependers
        when :due
          @ticket.due
        end
    end
    return value
  end

  def []=( id, value )
    # If the value is nil, delete the key (returning it to the current value)
    if value.nil?
      delete( id )
      return
    end

    attrInfo = ChangeAttributes[id]
    raise InvalidAttributeError.new( 'Unknown attribute' ) if attrInfo.nil?

    case attrInfo[:type]
    # If it's a list, make sure it's an array and every element of the array is allowed.
    when :list
      unless value.is_a? Array
        raise InvalidAttributeError.new( "Attribute #{id} must be an array." )
      end
      unless attrInfo[:allowed].nil?
        value.each do |listItem|
          unless attrInfo[:allowed].include? listItem
            raise InvalidAttributeError.new(
              "Item [#{listItem}] not in [#{attrInfo[:allowed]}]"
            )
          end
        end
      end

    # If it's an int, make sure the value is numeric
    when :int
      unless value.is_a?( Fixnum ) or value.to_s =~ /\d+/
        raise InvalidAttributeError.new( "Attribute #{id} must be an integer." )
      end
      value = value.to_i

    # If it's a text, make sure it's a one-line string
    when :text
      value = value.to_s
      if value.to_s =~ /\r|\n/
        raise InvalidAttributeError.new( "Attribute #{id} must be a one line string." )
      end

    # If it's a bigtext, just make it a string
    when :bigtext
      value = value.to_s

    # If it's a time, convert it to a Time object or false if empty.
    when :time
      if value.empty?
        value = false
      else
        begin
        value = Time.parse( value )
        rescue ArgumentError
          raise InvalidAttributeError.new( "Attribute #{id} is not a valid time string." )
        end
      end
    end # case

    # If the type isn't a list, we haven't yet checked if the value is allowed.
    if attrInfo[:type] != :list and attrInfo[:allowed] and !attrInfo[:allowed].include?( value )
      raise InvalidAttributeError.new(
        "Item [#{value}] not in [#{attrInfo[:allowed]}]"
      )
    end

    # If we make it here, the change is good.
    super( id, value )
  end

end
