require 'core/Database.rb'

require 'tickets/ListItem.rb'
require 'tickets/Project.rb'
require 'tickets/Status.rb'
require 'tickets/Keyword.rb'


module Test

  TestTable = "test_listitem"

  class ListItemForTesting < ListItem
    def self.tableName
      "test_listitem"
    end
  end

  class TestListItem < MiniTest::Unit::TestCase

    def testSubclassGetAll
      Database::DB.execute( "DELETE FROM #{TestTable} WHERE 1=1" )

      items = [
        { :name => "item1", :description => "the first item" },
        { :name => "item2", :description => "the second item" },
        { :name => "item3", :description => "the third item" },
      ]

      items.each do |item|
        addToList( TestTable, item[:name], item[:description] )
      end

      actualItems = ListItemForTesting.allItems
      assert_equal( items.length, actualItems.length, "different number of items" )

      expectedNames = items.map { |i| i[:name] }.sort
      actualNames = actualItems.map { |i| i.shortName }.sort
      assert_equal( expectedNames, actualNames, "list item names don't match" )

      expectedDescriptions = items.map { |i| i[:description] }.sort
      actualDescriptions = actualItems.map { |i| i.description }.sort
      assert_equal( expectedDescriptions, actualDescriptions, "list item descriptions don't match" )
    end

    def testHumanReadable
      shortName = String.randId
      description = String.randId

      item = ListItemForTesting.new( 0, shortName, description )
      assert_includes( item.to_s, shortName, "Human readable text missing the short name" )
      assert_includes( item.to_s, description, "Human readable text missing the description" )
    end

    def testOverlap
      # TODO: interlaced test
    end

    def testProject
      listTest( "projects", Project )
    end

    def testStatus
      listTest( "statuses", Status )
    end

    def testKeyword
      listTest( "keywords", Keyword )
    end

    def listTest( table, klass )
      shortName = String.randId
      description = String.randId

      addToList( table, shortName, description )

      found = false
      klass.allItems.each do |item|
        found ||= item.shortName == shortName && item.description == description
      end
      assert( found, "#{table.capitalize} not found in allItems" )

      # Clean up
      Database::DB.execute(
        "DELETE FROM #{table} WHERE name = :name AND description = :description",
        :name => shortName,
        :description => description,
      )
    end

    def addToList( table, shortName, description )
      Database::DB.execute(
        "INSERT INTO #{table} (name, description)
          VALUES (:name, :description)",
        :name => shortName,
        :description => description
      )
    end

  end
end
