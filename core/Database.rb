require 'sqlite3'
require 'core/Settings.rb'

module Database
  DB = SQLite3::Database.new( Settings::DATABASE_FILE )
end

Database::DB.results_as_hash = true
