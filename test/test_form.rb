require_relative 'helper'

require 'ippon/form'
require 'ippon/form_data'

class TestForm < Minitest::Test
  include Ippon::Form

  class User < Group
    fields(
      name: Text,
      skills: TextList,
      is_good: Flag,
    )

    validate do
      form(
        name: field(:name) | trim | required,
        skills: field(:skills) | for_each(trim | required),
      )
    end
  end

  def root_key
    Ippon::FormData::DotKey.new
  end

  def input(query_string)
    Ippon::FormData::URLEncoded.parse(query_string)
  end

  def test_basic_group
    user = User.new(root_key)
    user.from_input(input("name=%20Bob&skills=Programming%20&skills=Skating"))

    assert_equal " Bob", user.name.value
    assert_equal ["Programming ", "Skating"], user.skills.to_a
    assert_nil user.is_good.checked?

    result = user.validate
    assert result.valid?
    expected = {
      name: "Bob",
      skills: ["Programming", "Skating"]
    }
    assert_equal expected, result.value
  end

  def test_doesnt_allow_defining_fields_twice
    klass = Class.new(Group)
    klass.fields(name: Text)
    assert_raises do
      klass.fields(name: Text)
    end
  end
 
  def test_doesnt_allow_overriding_methods
    klass = Class.new(Group)
    assert_raises do
      klass.fields(to_s: Text)
    end
  end

  def test_requires_fields
    klass = Class.new(Group)
    assert_raises do
      klass.new(root_key)
    end
  end

  class Multi < Group
    fields(
      users: List[of: User],
      send_email: Flag,
    )

    validate do
      form(
        users: field(:users),
        send_email: field(:send_email),
      )
    end
  end

  def test_multi
    multi = Multi.new(root_key)
    multi.from_input(input("users=0&users.0.name=Bob&users.1.name=Alice&send_email=1"))

    assert_nil multi.result
    refute multi.error?

    result = multi.validate
    assert result.valid?

    refute_nil multi.result
    refute multi.error?

    value = result.value
    assert_equal 1, value[:users].size
    assert_equal "Bob", value[:users][0][:name]
  end

  def serialize(entry)
    pairs = []
    entry.serialize do |name, value|
      pairs << [name, value]
    end
    pairs
  end

  def test_serialize
    multi = Multi.new(root_key)

    user = multi.users.add
    user.name.value = "Bob"
    user.is_good.checked = true

    assert_equal [
      ["users", "0"],
      ["users.0.name", "Bob"],
      ["users.0.is_good", "1"],
    ], serialize(multi)
  end

  def test_serialize_flag
    entry = Flag.new(root_key["a"])
    assert_equal [], serialize(entry)

    entry.checked = true
    assert_equal [["a", "1"]], serialize(entry)

    entry.checked = false
    assert_equal [["a", "0"]], serialize(entry)
  end

  def test_serialize_text_list
    entry = TextList.new(root_key["a"])
    assert_equal [], serialize(entry)

    entry.values << "1"
    assert_equal [["a", "1"]], serialize(entry)

    entry.values << "1"
    assert_equal [["a", "1"], ["a", "1"]], serialize(entry)
  end

  def test_list_with_id
    entry = List[of: User].new(root_key["users"])
    user = entry.add

    rows = []
    entry.each_with_id do |*args|
      rows << args
    end

    assert_equal 1, rows.size
    assert_equal [user, "users", "0"], rows[0]
  end
end