require_relative 'helper'

require 'ippon/migrator'
require 'sequel'


class TestMigrator < Minitest::Test
  begin
    require 'jdbc/sqlite3'
    CONNECT_URL = 'jdbc:sqlite::memory:'
  rescue LoadError
    CONNECT_URL = 'sqlite:/'
  end

  def setup
    @db = Sequel.connect(CONNECT_URL)
    @migrator = Ippon::Migrator.new(@db)
  end

  def capture_out(&blk)
    out, _ = capture_io(&blk)
    out
  end

  def one
    @migrator.migrate "1-initial-schema" do |db|
      db.create_table(:users) do
        primary_key :id
        Text :name, null: false
      end
    end
  end

  def two
    @migrator.migrate "2-add-email" do |db|
      db.add_column(:users, :email, :text, unique: true)
    end
  end

  def capture_apply
    capture_out { @migrator.apply }
  end

  def test_simple_migration
    one

    assert_match "Migrating 1-initial-schema", capture_apply
  end

  def test_duplicate_migration
    one
    assert_raises(ArgumentError) { one }
  end

  def test_migrates_only_once
    one

    results = 3.times.map { capture_apply }

    assert_match "Migrating 1-initial-schema", results[0]
    assert_empty results[1]
    assert_empty results[2]
  end

  def test_incremental_migrating
    one
    assert_equal "[ ] Migrating 1-initial-schema\n", capture_apply

    two
    assert_equal "[ ] Migrating 2-add-email\n", capture_apply

    # no more
    assert_equal "", capture_apply
  end

  def test_summary
    one
    out = capture_out { @migrator.print_summary }

    assert_match(/1 migrations successfully loaded/, out)
    assert_match(/1-initial-schema not applied/, out)

    capture_apply
    out = capture_out { @migrator.print_summary }
    assert_match(/1 migrations successfully loaded/, out)
    refute_match(/1-initial-schema not applied/, out)
  end

  def test_load_directory_error
    assert_raises(ArgumentError) do
      # No such directory
      @migrator.load_directory(__dir__ + '/nope')
    end

    assert_raises(ArgumentError) do
      # A file, not a directory
      @migrator.load_directory(__FILE__)
    end
  end

  def test_load_directory
    out = capture_out do
      @migrator.load_directory(__dir__ + '/migrations')
      @migrator.print_summary
    end

    assert_match(/Loading .*\ba\.rb/, out)
    assert_match(/Loading .*\bb\.rb/, out)
    assert_match(/3 migrations successfully loaded/, out)
    assert_equal 3, @migrator.unapplied_names.size
  end
end

