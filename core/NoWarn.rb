
module NoWarn
  def self.noWarn
    backup = $VERBOSE
    $VERBOSE = nil
    yield
    $VERBOSE = backup
  end
end
