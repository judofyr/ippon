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

    schema = optional { |val| val % 2 == 0 }
    assert_instance_of Optional, schema
    assert_equal true, schema.predicate === 2

    schema = form(a: field("a")) & form(b: field("b"))
    assert_instance_of Merge, schema

    schema = for_each(number)
    assert_instance_of ForEach, schema
  end

  def test_validation_error
    err = assert_raises(ValidationError) do
      number.validate!("2b2")
    end

    assert_instance_of Result, err.result
    assert_equal 1, err.errors.size
  end

  def test_unhalt
    schema = match(1..20).unhalt | validate { |val| val % 2 == 0 }

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

    optional = Optional.new(predicate: proc { |val| val % 2 == 0 })
    result = optional.validate(6)
    assert result.halted?
    assert_nil result.value
  end

  def test_float
    assert_equal 125.0, float.validate!("125.0")
    assert_equal 12.5, float.validate!("12.5")
    assert_equal -12.5, float.validate!("-12.5")
    assert_equal 12.5, float.validate!("+12.5")

    result = float.validate("  12b3  ")
    assert result.error?
  end

  def test_number
    # Default ignore character
    assert_equal 1234, Number.new.validate!("12 34")

    result = Number.new.validate("$123")
    assert result.error?

    # Custom ignore character
    assert_equal 1234, Number.new(ignore: " $").validate!("$ 1 234")

    # Incorrect type of `ignore`
    assert_raises(ArgumentError) do
      Number.new(ignore: 123).validate!("123")
    end

    # Custom separator
    value = Number.new(decimal_separator: ",", convert: :rational).validate!("1,5")
    assert_equal Rational(3, 2), value

    # Fractional
    result = Number.new.validate("122.5")
    assert result.error?
    assert_equal "must be a number", result.errors[0].message

    assert_equal 122, Number.new.validate!("122.0")

    # Integer rounding
    assert_equal 123, Number.new(convert: :round).validate!("122.5")
    assert_equal 122, Number.new(convert: :floor).validate!("122.5")
    assert_equal 123, Number.new(convert: :ceil).validate!("122.2")

    # Unknown `convert`
    assert_raises(ArgumentError, /flor/) do
      Number.new(convert: :flor).validate!("122.5")
    end

    # Rational
    value = Number.new(convert: :rational).validate!("4.5")
    assert_instance_of ::Rational, value
    assert_equal Rational(9, 2), value

    # Float
    value = Number.new(convert: :float).validate!("4.5")
    assert_instance_of ::Float, value
    assert_equal 4.5, value

    # Decimal
    value = Number.new(convert: :decimal).validate!("4.5")
    assert_instance_of ::BigDecimal, value
    assert_equal BigDecimal.new("4.5"), value

    # Scaling
    value = Number.new(ignore: " $", scaling: 100).validate!("$ 1 234.10")
    assert_equal 123410, value

    result = Number.new(ignore: " $", scaling: 100).validate("$ 1 234.105")
    assert result.error?

    # Scaling with rounding
    value = Number.new(ignore: " $", scaling: 100, convert: :round).validate!("$ 1 234.105")
    assert_equal 123411, value

    value = Number.new(ignore: " $", scaling: 100, convert: :floor).validate!("$ 1 234.105")
    assert_equal 123410, value
    
    value = Number.new(ignore: " $", scaling: 100, convert: :ceil).validate!("$ 1 234.101")
    assert_equal 123411, value
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
    assert_equal "must match 123", result.errors[0].message
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

  def test_transform
    transform = Transform.new(handler: proc { |val| val * 2 })

    assert_equal 4, transform.validate!(2)
  end

  def test_form
    form = Form.new(
      name: field("name") | trim | required,
      bio: field("bio") | trim,
      karma: field("karma") | trim | optional | number,
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
      karma: field("karma") | trim | optional | number,
    )

    schema = Merge.new(form1, form2)

    value = schema.validate!(
      "name" => "Magnus",
      "bio" => "Programmer  ",
      "karma" => " 4"
    )

    assert_equal({name: "Magnus", bio: "Programmer", karma: 4}, value)
  end

  def test_for_each
    schema = ForEach.new(trim | required | number)

    result = schema.validate(["1", "2 2"])
    assert result.valid?
    assert_equal [1, 22], result.value

    result = schema.validate(["1", "2b2"])
    assert result.error?
    assert_equal [1, "2b2"], result.value

    error = result.errors[0]
    assert_equal [1], error.path
  end
end

