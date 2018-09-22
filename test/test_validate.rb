require_relative 'helper'

require 'ippon/validate'

class TestValidate < Minitest::Test
  include Ippon::Validate
  include Builder

  def test_basic_field
    field = field("name") | trim | required

    result = field.validate({"name" => "  Magnus "})
    assert result.success?
    assert_equal "Magnus", result.value

    result = field.validate({"name" => "   "})
    assert result.error?

    error = result.errors[0]
    assert_equal [], error.path
    assert_equal "is required", error.message
  end

  def test_helpers
    schema = field("name", message: "yes")
    assert_instance_of Field, schema
    assert_equal "name", schema.props[:key]
    assert_equal "yes", schema.props[:message]

    schema = form(a: field("a"))
    assert_instance_of Form, schema
    assert_equal [:a], schema.fields.keys

    schema = transform { |val| val * 2 }
    assert_instance_of Transform, schema
    assert schema.props[:handler]

    schema = field("name") | required
    assert_instance_of Sequence, schema

    schema = form(a: field("a")) & form(b: field("b"))
    assert_instance_of Merge, schema

    schema = halt_if { |val| val % 2 == 0 }
    assert_instance_of Halt, schema
  end

  def test_unhalt
    schema = match(1..20).unhalt | match_with { |val| val % 2 == 0 }

    result = schema.validate(55)
    assert result.error?
    assert_equal 2, result.errors.size

    result = schema.validate(54)
    assert result.error?
    assert_equal 1, result.errors.size

    result = schema.validate(15)
    assert result.error?
    assert_equal 1, result.errors.size

    schema.validate!(10)
  end

  def test_field_with_hash
    fetch = Field.new(key: "name")
    assert_equal "Magnus", fetch.validate!({"name" => "Magnus"})
  end

  def test_field_custom
    fetch = Field.new(key: "name")
    obj = Object.new
    def obj.[](key)
      key.upcase
    end

    assert_equal "NAME", fetch.validate!(obj)
  end

  def test_trim
    trim = Trim.new

    assert_equal "123", trim.validate!("123")
    assert_equal "123", trim.validate!("  123  ")
    assert_equal "1 2 3", trim.validate!("  1 2 3  ")
    assert_nil trim.validate!("\t  \t ")
  end

  def test_optional
    optional = Optional.new

    result = optional.validate("123")
    refute result.halted?

    result = optional.validate("")
    refute result.halted?

    result = optional.validate(nil)
    assert result.halted?
  end

  def test_integer
    integer = Integer.new

    assert_equal 123, integer.validate!("123")
    assert_equal -123, integer.validate!("-123")
    assert_equal 123, integer.validate!("+123")

    result = integer.validate("  12 3  ")
    assert result.error?
    assert_equal "must be an integer", result.errors[0].message
  end

  def test_boolean
    boolean = Boolean.new

    assert_equal false, boolean.validate!(nil)
    assert_equal false, boolean.validate!(false)
    assert_equal true,  boolean.validate!("")
    assert_equal true,  boolean.validate!("1")
    assert_equal true,  boolean.validate!("false")
  end

  def test_match
    match = Match.new(predicate: 123)

    assert_equal 123, match.validate!(123)
    result = match.validate(124)
    assert result.error?
  end

  def test_match_custom
    obj = Object.new
    def obj.===(other)
      (other % 2) == 0
    end
    match = Match.new(predicate: obj)

    assert_equal 124, match.validate!(124)
    result = match.validate(125)
    assert result.error?
  end

  def test_halt
    obj = Object.new
    def obj.===(other)
      (other % 2) == 0
    end
    halt = Halt.new(predicate: obj)

    result = halt.validate(12)
    assert result.valid?
    assert result.halted?

    result = halt.validate(13)
    assert result.valid?
    refute result.halted?
  end

  def test_transform
    transform = Transform.new(handler: proc { |val| val * 2 })

    assert_equal 4, transform.validate!(2)
  end

  def test_form
    form = Form.new(
      name: field("name") | trim | required,
      bio: field("bio") | trim,
      karma: field("karma") | trim | optional | integer,
    )

    value = form.validate!(
      "name" => "Magnus",
      "bio" => "Programmer  ",
      "karma" => " 4"
    )

    assert_equal({name: "Magnus", bio: "Programmer", karma: 4}, value)

    result = form.validate(
      "name" => "  ",
      "bio" => "Programmer  ",
      "karma" => " abc"
    )
    assert result.error?
    assert_equal 2, result.errors.size

    err1, err2 = result.errors
    assert_equal [:name], err1.path
    assert_equal [:karma], err2.path
  end

  def test_merge
    form1 = form(
      name: field("name") | trim | required,
      bio: field("bio") | trim,
    )

    form2 = form(
      karma: field("karma") | trim | optional | integer,
    )

    schema = Merge.new(form1, form2)

    value = schema.validate!(
      "name" => "Magnus",
      "bio" => "Programmer  ",
      "karma" => " 4"
    )

    assert_equal({name: "Magnus", bio: "Programmer", karma: 4}, value)
  end
end

