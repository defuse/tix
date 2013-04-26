require 'etc'

class User
  def self.getlogin
    login = Etc.getlogin
    fixed = ""
    login.each_char do |c|
      fixed << c
    end
    return fixed
  end
end
