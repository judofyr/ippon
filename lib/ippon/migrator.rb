require 'ippon'
require 'set'

# Migrator provides a migration system on top of {http://sequel.jeremyevans.net/
# Sequel}. It should be trivial to add if you're already using Sequel to access
# your database, but you can also use it to migrate a database your primarily
# accessing through other means.
#
# Migrator provides a way to write migrations in a single file (no generators
# required) and you can integrate it in any system in minutes. As your
# application grows, it provides ways to structure migrations in multiple files.
#
# == Getting started
#
# To get started created a file called +migrate.rb+ and populate it:
#
#   require 'ippon/migrator'
#   require 'something_that_connects_to_your_database'
#
#   db = Sequel::DATABASES.last  # if you don't have access to it directly
#
#   m = Ippon::Migrator.new(db)
#
#   m.migrate "1-initial-schema" do |db|
#     db.create_table(:users) do
#       primary_key :id
#       Text :email, null: false, unique: true
#       Text :crypted_password
#     end
#   end
#
#   m.print_summary
#   m.apply
#
# You can now run it once to migrate,
#
#   $ ruby migrate.rb
#   ** 1 migrations successfully loaded
#   ** Migrating 1-initial-schema
#
# and another time to see that it's not running the migration twice:
#
#   $ ruby migrate.rb
#   ** 1 migrations successfully loaded
#
# Append +migrate.rb+ to add another migration. It's very important to not
# remove the previous migrations as the migrator needs to know about _all_
# migrations to work correctly. You should also be aware that the number "2" in
# the migration name below is not significant, and it's only the ordering of the
# {#migrate} calls that matter.
#
#   m.migrate "2-add-bio" do |db|
#     db.add_column(:users, :bio, :text)
#   end
#
# We will now see the following:
#
#   $ ruby migrate.rb
#   ** 2 migrations successfully loaded
#   ** Migrating 2-add-bio
#
# == Moving into files
#
# After working with this system you will find that having the migrations in a
# single file is quite convenient. You don't need to worry about generators, and
# if you forgot the correct way create/remove/alter columns, you can easily peek
# at the recent migrations.
#
# At a certain point however, the file become very large and hard to work with.
# Migrator provides a helper method {#load_directory} to help you split out into
# multiple files:
#
#   # migrate.rb
#
#   # (same setup as earlier)
#
#   m = Ippon::Migrator.new(db)
#   m.load_directory(__dir__ + "/migrations")
#   m.print_summary
#   m.apply
#
#   # migrations/2018-01.rb
#
#   migrate "1-initial-schema" do |db|
#     db.create_table(:users) do
#       primary_key :id
#       Text :email, null: false, unique: true
#       Text :crypted_password
#     end
#   end
#
#   migrate "2-add-bio" do |db|
#     db.add_column(:users, :bio, :text)
#   end
#
# It's up to you to decide how to structure the files themselves.  Migrator will
# load the files in order based on the filename, and the rest of the structuring
# is left to you. You might prefer to have one migration per file, one file per
# month, or split it manully into smaller files when you think it's too large.
# Because the migration name is in the code (and not dependent on the filename)
# you can always restructure later.
#
# == Key concepts
#
# You need to know the following concepts:
#
# - The migrator stores a list of _migrations_.
# - Every migration has a _name_ (string) and some _code_ which tells how to
#   apply it.
# - You use {#migrate} to declare migrations. The order in which you call this
#   method decides the order in which migrations are applied.
# - The migration name must be globally unique. It's recommended to use some
#   sort of manual counter: "2-add-name". This ensures that if you five months
#   later add a migration named "add-name" it won't collide with older migrations.
# - Note that the migration counter is not significant in any other way. If two
#   developers create the migrations "2-add-name" and "2-add-bio" in different
#   branches, you should _not_ rename one of them to "3". You should only make
#   sure that they are declared in a correct order.
# - Use {#load_directory} to load migrations from different files.
# - You can use {#unapplied_names} to see if there are migrations that haven't
#   been applied yet. You can for instance check this right before you boot your
#   web server (or run your test suite) to verify that your database is
#   correctly migrated.
# - The migrator stores information about the currently applied migrations in
#   the +schema_migrations+ table. This is created for you. Never touch this
#   table manually.
#
class Ippon::Migrator
  # @param db [Sequel::Database]
  def initialize(db)
    @db = db
    @seen = Set.new
    @migrations = []
  end

  # Stores information about a single migration. This is currenly not exposed as
  # a part of the public API.
  #
  # @api private
  # @!attribute name
  #   @return [String] migration name
  # @!attribute code
  #   @return [Proc] migration code
  Migration = Struct.new(:name, :code)

  # Defines a migration.
  #
  # @param name [#to_s] name of the migration
  # @yield [db] database instance (inside a transaction) where you can
  #   apply your migration
  # @raise [ArgumentError] if there is another migration defined with
  #   the same name
  def migrate(name, &blk)
    name = name.to_s

    if @seen.include?(name)
      raise ArgumentError, "duplicate migration: #{name}"
    end

    @seen << name
    @migrations << Migration.new(name, blk)
    nil
  end

  # Applies the loaded migrations to the database.
  def apply
    @migrations.each do |migration|
      apply_migration(migration)
    end
    nil
  end

  # Returns migrations that have not yet been applied to the database.
  #
  # @example Verify that the database is correctly migrated
  #   if !migrator.unapplied_names.empty?
  #     migrator.print_summary
  #     raise "Unapplied migrations. Cannot load application."
  #   end
  #
  # @return [Array<String>] migrations that have not been applied to the database.
  def unapplied_names
    seen = dataset.select_map(:name).to_set
    @migrations
      .select { |migration| !seen.include?(migration.name) }
      .map { |migration| migration.name }
  end

  # Prints a summary of how many migrations were successfully loaded, together with
  # a list of the migrations that have not yet been applied to the database.
  #
  # @example
  #   migrator = Ippon::Migrator.new(db)
  #   migrator.load_directory(__dir__ + "/migrations")
  #   migrator.print_summary
  #
  #   # Prints:
  #   # ** 10 migrations successfully loaded
  #   # !! 1-initial-schema not applied
  def print_summary
    puts "[ ] #{@migrations.size} migrations successfully loaded"
    unapplied_names.each do |name|
      puts "[!] #{name} not applied"
    end
  end

  # @raise [ArgumentError] if dir is not a directory or doesn't exist
  def load_directory(dir)
    if !File.directory?(dir)
      raise ArgumentError, "#{dir} is not a directory"
    end

    files = Dir[File.join(dir, "*.rb")]
    files.sort.each do |path|
      puts "[ ] Loading #{path}"
      instance_eval(File.read(path), path)
    end

    nil
  end

  private

  def apply_migration(migration)
    @db.transaction do
      if dataset.where(name: migration.name).first
        # Already inserted
      else
        puts "[ ] Migrating #{migration.name}"
        migration.code.call(@db)
        dataset.insert(name: migration.name)
        # Successfully migrated
      end
    end
  end

  def setup_schema
    @db.create_table?(:schema_migrations) do
      Text :name, primary_key: true, null: false
    end
    @db[:schema_migrations]
  end

  def dataset
    @dataset ||= setup_schema
  end
end

