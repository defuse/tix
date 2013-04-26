require 'terminfo' # the ruby-terminfo gem

# TODO: should the search filter be remembered?
# TODO: flash should be a class variable so client code doesn't have to repeat the common flash code

class CLIMenu

  DefaultMarker = "->"

  class MenuItem
    attr_accessor :key, :text
    def initialize( key, text )
      @key = key
      @text = text
    end
  end

  attr_accessor :prompt

  def initialize
    @items = []
    @position = 0
    @persistent = []
    @defaultItem = nil
    @header = nil
    @headerLines = 0
    @prompt = 'choice/filter'
  end

  def add( key, text, default = false )
    item =  MenuItem.new( key, text.to_s )
    @items << item
    @defaultItem = item if default
  end

  def addPersistent( key, text, default = false )
    item =  MenuItem.new( key, text.to_s )
    @persistent << item
    @defaultItem = item if default
  end

  def header=( str )
    if str.nil?
      @header = nil
      @headerLines = 0
    else
      @header = str.rstrip
      @headerLines = @header.count "\n"
    end
  end

  def header
    @header
  end

  def position=( index )
    raise 'Invalid index' if index != 0 and ( index < 0 or index >= @items.length )
    @position = index
  end

  def position
    @position
  end

  def show( flash = nil )
    itemsShown = 0
    loop do
      CLIMenu.clear
      choiceOffset = @position

      begin
        itemsShown = itemsToShow()
        itemsShown -= 2 unless flash.nil?
        if itemsShown < 1
          print "Your terminal is too small. Please enlarge it and press ENTER to continue."
          STDIN.gets
        end
      end while itemsShown < 1
      
      print "=" * CLIMenu.cols() + "\n\n"

      unless @header.nil?
        print @header + "\n\n"
      end

      1.upto( itemsShown ) do |i|
        index = @position + i - 1
        if index >= @items.length
          itemsShown = i - 1
          break
        end
        item = @items[index]
        marker = ( item == @defaultItem ) ? DefaultMarker : "" 
        number = "%#{DefaultMarker.length}s%3d. " % [marker, i]
        itemText = item.text.clone
        if number.length + itemText.length > CLIMenu.cols()
          dotStart = CLIMenu.cols() - number.length - 3 # 3 dots
          if dotStart >= 0 and dotStart < itemText.length
            itemText[dotStart..itemText.length] = "..."
          end
        end
        puts number + itemText
      end

      unless @persistent.empty?
        print "\n"
        @persistent.each_with_index do |item, i|
          marker = ( item == @defaultItem ) ? DefaultMarker : "" 
          puts "%#{DefaultMarker.length}s%3d. %s" % [marker, itemsShown + i + 1, item.text]
        end
      end

      puts "\nDefault: #{@defaultItem.text}" unless @defaultItem.nil?

      if flash
        puts "\n" + flash
        flash = nil
      end

      loop do
        puts "\nCommands: 'q': Quit, 'Q': QuitProg, 'f' or [space]: Forward, 'b' or '-': Back"
        prompt = ( @prompt.empty? ) ? "" : @prompt + " "
        positionDisplay =  "(#{@position+1}-#{@position+itemsShown} of #{@items.length})"
        print "#{positionDisplay} #{prompt}>> "

        choice = STDIN.gets.chop

        # Handle this one separately so the others can ignore whitespace
        if choice == 'f' or choice =~ /^\s+$/
          unless @position + itemsShown >= @items.length
            @position += itemsShown
          end
          break # break out of the inner loop
        end

        choice.strip!

        case choice
        when "q"
          return nil
        when "Q"
          exit
        when "-", "b", "B"
          # We want the first item shown this time to be the successor of the
          # last item shown next time.
          @position -= itemsToShow()
          @position = 0 if @position < 0
          break # break out of the inner loop
        when ""
          return @defaultItem.key unless @defaultItem.nil?
          puts " ** Please select an item ** "
        when /^\d+$/
          num = choice.to_i
          if num >= 1 and num <= itemsShown
            return @items[choiceOffset + num - 1].key
          elsif num > itemsShown and num - itemsShown <= @persistent.length
            return @persistent[num - itemsShown - 1].key
          else
            puts " ** Invalid choice ** "
          end
        else
          item = filterOn( choice )
          if item == :_nomatch_climenu_1z1z
            flash = " ** No items match [#{choice}] **"
          elsif item == :_regexperror_climenu_1z1z
            flash = " ** '#{choice}' is not a valid regular expression. **"
          else
            return item.key unless item.nil?
          end
          break
        end # case
      end # re-prompt loop
    end # main pager loop
  end

  # Displays a new menu with only the items whose text matches the search
  # parameter, which can either be a Regexp object or a string containing a
  # ruby-syntax regular expression.
  def filterOn( search )
    unless search.is_a? Regexp
      searchRegexp = Regexp.new( search, Regexp::IGNORECASE )
    end

    menu = CLIMenu.new
    menu.header = ( @header.nil? ? "" : @header + "\n\n" ) + "    ( filter: '#{search}' )"
    menu.prompt = @prompt

    items = 0
    @items.each do |item|
      next unless searchRegexp =~ item.text.to_s
      menu.add( item, item.text, false )
      items += 1
    end
    return :_nomatch_climenu_1z1z if items == 0

    @persistent.each do |item|
      menu.addPersistent( item, item.text, false )
    end
    menu.addPersistent( :_unfilter_climenu_1z1z, 'Clear filter', true )

    item = menu.show
    if item == :_unfilter_climenu_1z1z or item == nil
      return nil
    else
      return item
    end
  rescue RegexpError
    return :_regexperror_climenu_1z1z
  end

  def itemsToShow
    toShow = CLIMenu.rows() - 6
    unless @persistent.empty?
      toShow = toShow - @persistent.length - 1
    end
    unless @header.nil?
      toShow = toShow - @headerLines - 2
    end
    return toShow
  end
  private :itemsToShow

  def self.clear
    print "\n" * rows()
  end

  def self.rows
    TermInfo.screen_size[0]
  end

  def self.cols
    TermInfo.screen_size[1]
  end

  def self.optionPrompt( prompt, letters )
    loop do
      default = ""
      letters.each do |letter|
        if letter =~ /[A-Z]/
          default = letter
        end
      end

      print prompt + " [" + letters.join('/') + "]  "
      letter = STDIN.gets.strip
      print "\n\n"

      letter = default if letter.empty?

      if letters.include?( letter.downcase ) or letters.include?( letter.upcase )
        return letter.downcase
      end
    end
  end

  # TODO: the behaviour of this method has changed, update everything else
  def self.prompt( prompt )
    value = nil
    loop do
      print prompt + "  "

      value = STDIN.gets
      if value.nil?
        return ""
      else
        value.chop!
      end

      print "\n"

      if block_given?
        break if yield( value )
        puts "Invalid. Retry."
      else
        break
      end
    end
    return value
  end

  def self.radioButtonMenu( prompt, choices, selected )
    oldSelected = selected
    loop do
      list = CLIMenu.new
      choices.each do |item|
        checkbox = (selected == item  ? "(X) " : "( ) ")
        list.add( item, checkbox + item.to_s )
      end
      list.addPersistent( :save, 'Save', true )
      list.addPersistent( :cancel, 'Cancel' )

      puts prompt 
      choice = list.show

      case choice
      when :save
        return selected
      when nil, :cancel
        return oldSelected
      else
        selected = choice
      end
    end # loop
  end

  # If given a block, will yield to it when the user selects 'Add new'
  # and the item (or array of items) returned from the block will be added.
  # If the block returns nil, no items will be added.
  # If no block is given, 'Add new' will just prompt the user for a string.
  def self.freeListEditor( prompt, selected )
    selected ||= []
    oldSelected = selected
    selected = selected.clone

    loop do
      list = CLIMenu.new
      list.prompt = 'delete/filter:'
      selected.each_with_index do |item, index|
        list.add( index, item )
      end
      list.addPersistent( :add, 'Add new...' )
      list.addPersistent( :save, 'Save', true )
      list.addPersistent( :cancel, 'Cancel' )
      choice = list.show
      if choice == :save
        return selected
      elsif choice == :add
        if block_given?
          toAdd = yield
          unless toAdd.nil?
            toAdd = [toAdd] unless toAdd.is_a? Array
            selected |= toAdd
          end
        else
          item = CLIMenu.prompt( 'New item:' )
          selected |= [item] unless item.empty?
        end
      elsif choice == :cancel or choice.nil?
        return oldSelected
      else
        selected.delete_at( choice )
      end
    end
  end

  # TODO: test me that I return the OBJECT in choices, not it's to_s or anything
  def self.checkboxMenu( prompt, choices, selected, header = nil )
    selected ||= []
    oldSelected = selected
    selected = selected.clone
    loop do
      list = CLIMenu.new
      list.prompt = prompt
      list.header = header
      choices.each do |item|
        checkbox = selected.include?( item ) ? "[X] " : "[ ] "
        list.add( item, checkbox + item.to_s )
      end
      list.addPersistent( :save, 'Save', true )
      list.addPersistent( :cancel, 'Cancel' )

      choice = list.show

      case choice
      when :save
        return selected
      when :cancel, nil
        return oldSelected
      else
        if selected.include? choice
          selected.delete( choice )
        else
          selected.push( choice )
        end
      end
    end # loop
  end

end
