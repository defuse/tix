
class Mail

  class IncompleteMailError < StandardError; end

  attr_accessor :to, :subject, :message

  def initialize
    @to = nil
    @subject = nil
    @message = nil
  end

  def send
    if [@to, @subject, @message].include? nil
      raise IncompleteMailError.new
    end

    IO.popen( ["mail", @to, "-s", @subject], "w" ) do |mail|
      mail.print @message
    end
  end

end
