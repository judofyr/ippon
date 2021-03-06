require_relative 'helper'

require 'ippon/form_data'

class TestFormData < Minitest::Test
  include Ippon::FormData

  def test_basic_parse
    form_data = URLEncoded.parse("a=1&b=2&a=3")

    assert_equal "1", form_data["a"]
    assert_equal "2", form_data["b"]
    assert_nil form_data["c"]

    assert_equal ["1", "3"], form_data.fetch_all("a")
  end

  def test_fetch
    form_data = URLEncoded.parse("a=1&b=2&a=3")

    assert_raises(KeyError) do
      form_data.fetch("c")
    end
  end

  def test_fetch_key
    root = DotKey.new

    form_data = URLEncoded.parse("name=Bob&address.street=Obo")
    assert_equal "Bob", form_data[root[:name]]

    address = root[:address]
    assert_equal "Obo", form_data[address[:street]]
  end

  def test_fetch_bracket_key
    root = BracketKey.new

    form_data = URLEncoded.parse("name=Bob&address[street]=Obo")
    assert_equal "Bob", form_data[root[:name]]

    address = root[:address]
    assert_equal "Obo", form_data[address[:street]]
  end
end

