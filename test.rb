$LOAD_PATH << File.dirname( __FILE__ )

require 'minitest/autorun'
require 'minitest/pride'
require 'fileutils'

$DATABASE_OVERRIDE = 'tix-test.db'
FileUtils::cp( 'tix-original.db', $DATABASE_OVERRIDE )
require 'core/Database.rb'


class String
  def self.randId( entropy = 64 )
    rand( 2 ** entropy ).to_s(36).upcase
  end
end

# Make assert_equal failures look better
require 'awesome_print'
module MiniTest::Assertions
  def mu_pp( obj )
    obj.awesome_inspect
  end
end

ARGV.each do |test|
  require test
end

