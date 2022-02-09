require_relative "helper"

require "ippon/migrations"
require "sequel"

class TestMigrations < Minitest::Test
  begin
    require "jdbc/sqlite3"
    CONNECT_URL = "jdbc:sqlite::memory:"
  rescue LoadError
    CONNECT_URL = "sqlite:/"
  end

  def setup
    @db = Sequel.connect(CONNECT_URL)
    @migrations = Ippon::Migrations.new
  end

  def one
    @migrations.migrate "1-initial-schema" do |db|
      db.create_table(:users) do
        primary_key :id
        Text :name, null: false
      end
    end
  end

  def two
    @migrations.migrate "2-add-email" do |db|
      db.add_column(:users, :email, :text, unique: true)
    end
  end

  def apply
    @migrations.apply_to(@db)
  end

  def test_simple_migration
    one
    refute @db.table_exists?(:schema_migrations)
    refute @db.table_exists?(:users)
    apply
    assert @db.table_exists?(:users)
    assert @db.table_exists?(:schema_migrations)
    assert_equal ["1-initial-schema"], @db[:schema_migrations].select_map(:name)
  end

  def test_duplicate_migration
    one
    assert_raises(ArgumentError) { one }
  end

  def test_migrates_only_once
    one
    apply
    apply
    apply
  end

  def test_incremental_migrating
    one
    apply
    assert_equal [], @migrations.unapplied_names(@db)
    two
    assert_equal ["2-add-email"], @migrations.unapplied_names(@db)
    apply
    @db[:users].insert(name: "Bob", email: "bob@example.com")
  end

  def test_load_directory_error
    assert_raises(ArgumentError) do
      # No such directory
      @migrations.load_directory(__dir__ + "/nope")
    end

    assert_raises(ArgumentError) do
      # A file, not a directory
      @migrations.load_directory(__FILE__)
    end
  end

  def test_load_directory
    @migrations.load_directory(__dir__ + "/migrations")
    assert_equal 3, @migrations.unapplied_names(@db).size
  end
end
