require 'tickets/Ticket.rb'
require 'ui/CLIMenu.rb'
require 'ui/TicketEditor.rb'
require 'ui/DependencyViewer.rb'

class TicketViewer

  def initialize( ticket )
    @ticket = ticket
  end

  def runUI
    menu = CLIMenu.new
    menu.header = @ticket.headers
    menu.add( :changelog, 'View changelog' )
    menu.add( :edit, 'Update ticket' )
    menu.add( :dependencies, 'View dependencies' )
    menu.add( :dependers, 'View dependers' )
    menu.add( :attachFile, 'Attach a file' )
    menu.add( :getFile, 'Retrieve an attached file' )
    flash = ""
    loop do
      choice = menu.show( flash )
      flash = ""
      case choice
      when :changelog
        @ticket.showChangeLog
      when :edit
        TicketEditor.new( @ticket ).runUI
        menu.header = @ticket.headers
      when :dependencies
        DependencyViewer.new( @ticket, :dependencies ).runUI
      when :dependers
        DependencyViewer.new( @ticket, :dependers ).runUI
      when :attachFile
        path = CLIMenu.prompt( "File path:" ) do |p|
          if p.empty?
            true # So they can quit the menu
          else
            File.exists? File.expand_path( p )
          end
        end

        # TODO: Handle IO errors better
        unless path.empty?
          @ticket.attachFile( File.expand_path( path ) )
          flash = " ** File attached. **"
        end
      when :getFile
        selectFile = CLIMenu.new
        menu.header = "Select a file:"
        @ticket.attachedFileList.each do |name|
          selectFile.add( name, name )
        end
        choice = selectFile.show
        if choice
          path = @ticket.getAttachedFile( choice, Dir.getwd )
          flash = "The file has been copied to your current working directory."
        end
      when nil
        break
      end
    end
  end

end
