require 'tickets/Ticket.rb'
require 'ui/TicketDisplayWrapper.rb'
require 'ui/CLIMenu.rb'

# Don't warn about circular dependencies when TicketViewer uses this class. 
require 'core/NoWarn.rb'
NoWarn::noWarn do
  require 'ui/TicketViewer.rb'
end

class DependencyViewer

  def initialize( rootTicket, type )
    raise 'Invalid type' unless [:dependencies, :dependers].include? type
    @root = rootTicket
    @type = type
  end

  def runUI
    menu = CLIMenu.new
    if @type == :dependencies
      menu.header = "Tickets depended on by #{@root.id}:"
    elsif @type == :dependers
      menu.header = "Tickets that depend on #{@root.id}:"
    end

    addDependencies( @root, menu )

    loop do
      result = menu.show
      case result
      when Ticket
        TicketViewer.new( result ).runUI
      when nil
        break
      end
    end
  end

  private

  def addDependencies( ticket, menu, level = 0 )
    # Add the 'root'
    wrapper = TicketDisplayWrapper.new( ticket ) do |t|
      display = t.description + "  (#{t.id})"
      if level > 0
        ("|   " * (level - 1)) + "|---" + display
      else
        display
      end
    end
    menu.add( ticket, wrapper )

    # Add all of its dependencies on the next level
    deps = (@type == :dependencies) ? ticket.dependencies : ticket.dependers
    deps.each do |dep|
      dep = Ticket.new( dep )
      addDependencies( dep, menu, level + 1 )
    end
  end

end
