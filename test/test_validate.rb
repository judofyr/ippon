require_relative 'helper'

require 'ippon/validate'

class TestValidate < Minitest::Test
  include Ippon::Validate
  include Builder

  def test_basic_fetch
    fetch = fetch("name") | trim | required

    result = fetch.validate({"name" => "  Magnus "})
    assert result.success?
    assert_equal "Magnus", result.value

    result = fetch.validate({"name" => "   "})
    assert result.error?

    step, path = result.step_errors[0]
    assert_equal [], path
    assert_equal "is required", step.message

    assert_equal "is required", result.error_messages[0]
  end

  def test_helpers
    schema = form(a: fetch("a")) & form(b: fetch("b"))
    assert_instance_of Merge, schema

    schema = for_each(number)
    assert_instance_of ForEach, schema
  end

  def test_validation_error
    err = assert_raises(ValidationError) do
      number.validate!("2b2")
    end

    assert_instance_of Result, err.result
    assert_equal 1, err.errors.steps.size
  end

  def test_unhalt
    schema = match(1..20).unhalt | validate { |val| val % 2 == 0 }

    result = schema.validate(55)
    assert result.error?
    assert_equal 2, result.errors.steps.size

    result = schema.validate(54)
    assert result.error?
    assert_equal 1, result.errors.steps.size

    result = schema.validate(15)
    assert result.error?
    assert_equal 1, result.errors.steps.size

    schema.validate!(10)
  end

  def test_fetch_with_hash
    schema = fetch("name")
    assert_equal "Magnus", schema.validate!({"name" => "Magnus"})
  end

  def test_fetch_failure
    schema = fetch("name")

    result = schema.validate({})
    assert result.error?
    assert_equal :fetch, result.errors.steps[0].type
  end

  def test_fetch_custom
    schema = fetch("name")
    obj = Object.new
    def obj.fetch(key)
      key.upcase
    end

    assert_equal "NAME", schema.validate!(obj)
  end

  def test_trim
    assert_equal "123", trim.validate!("123")
    assert_equal "123", trim.validate!("  123  ")
    assert_equal "1 2 3", trim.validate!("  1 2 3  ")
    assert_nil trim.validate!("\t  \t ")
  end

  def test_optional
    result = optional.validate("123")
    refute result.halted?

    result = optional.validate("")
    refute result.halted?

    result = optional.validate(nil)
    assert result.halted?

    result = optional { |val| val % 2 == 0 }.validate(6)
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
    assert_equal 1234, number.validate!("12 34")

    result = number.validate("$123")
    assert result.error?

    # Custom ignore character
    assert_equal 1234, number(ignore: " $").validate!("$ 1 234")

    # Incorrect type of `ignore`
    assert_raises(ArgumentError) do
      number(ignore: 123).validate!("123")
    end

    # Custom separator
    value = number(decimal_separator: ",", convert: :rational).validate!("1,5")
    assert_equal Rational(3, 2), value

    # Fractional
    result = number.validate("122.5")
    assert result.error?
    assert_equal "must be a number", result.errors.steps[0].message

    assert_equal 122, number.validate!("122.0")

    # Integer rounding
    assert_equal 123, number(convert: :round).validate!("122.5")
    assert_equal 122, number(convert: :floor).validate!("122.5")
    assert_equal 123, number(convert: :ceil).validate!("122.2")

    # Unknown `convert`
    assert_raises(ArgumentError, /flor/) do
      number(convert: :flor).validate!("122.5")
    end

    # Rational
    value = number(convert: :rational).validate!("4.5")
    assert_instance_of ::Rational, value
    assert_equal Rational(9, 2), value

    # Float
    value = number(convert: :float).validate!("4.5")
    assert_instance_of ::Float, value
    assert_equal 4.5, value

    # Decimal
    value = number(convert: :decimal).validate!("4.5")
    assert_instance_of ::BigDecimal, value
    assert_equal BigDecimal("4.5"), value

    # Scaling
    value = number(ignore: " $", scale: 100).validate!("$ 1 234.10")
    assert_equal 123410, value

    result = number(ignore: " $", scale: 100).validate("$ 1 234.105")
    assert result.error?

    # Scaling with rounding
    value = number(ignore: " $", scale: 100, convert: :round).validate!("$ 1 234.105")
    assert_equal 123411, value

    value = number(ignore: " $", scale: 100, convert: :floor).validate!("$ 1 234.105")
    assert_equal 123410, value
    
    value = number(ignore: " $", scale: 100, convert: :ceil).validate!("$ 1 234.101")
    assert_equal 123411, value
  end

  def test_boolean
    assert_equal false, boolean.validate!(nil)
    assert_equal false, boolean.validate!(false)
    assert_equal true,  boolean.validate!("")
    assert_equal true,  boolean.validate!("1")
    assert_equal true,  boolean.validate!("false")
  end

  def test_match
    schema = match(123)

    assert_equal 123, schema.validate!(123)
    result = schema.validate(124)
    assert result.error?
    assert_equal "must match 123", result.errors.steps[0].message
  end

  def test_match_custom
    obj = Object.new
    def obj.===(other)
      (other % 2) == 0
    end
    schema = match(obj)

    assert_equal 124, schema.validate!(124)
    result = schema.validate(125)
    assert result.error?
  end

  def test_transform
    schema = transform { |val| val * 2 }

    assert_equal 4, schema.validate!(2)
  end

  def test_form
    schema = form(
      name: fetch("name") | trim | required,
      bio: fetch("bio") | trim,
      karma: fetch("karma") | trim | optional | number,
    )

    value = schema.validate!(
      "name" => "Magnus",
      "bio" => "Programmer  ",
      "karma" => " 4"
    )

    assert_equal({name: "Magnus", bio: "Programmer", karma: 4}, value)

    result = schema.validate(
      "name" => "  ",
      "bio" => "Programmer  ",
      "karma" => " abc"
    )
    assert result.error?
    assert_equal 2, result.step_errors.size

    err1, err2 = result.step_errors
    assert_equal [:name], err1[1]
    assert_equal [:karma], err2[1]

    assert_equal 1, result.errors[:name].steps.size
    assert_equal 1, result.errors[:karma].steps.size
  end

  Person = Struct.new(:name, :bio, :karma)

  def test_form_with_attributes
    schema = form { Person.new }.with_attrs(
      name: fetch("name") | trim | required,
      bio: fetch("bio") | trim,
      karma: fetch("karma") | trim | optional | number,
    )

    value = schema.validate!(
      "name" => "Magnus",
      "bio" => "Programmer  ",
      "karma" => " 4"
    )

    assert_instance_of Person, value
    assert_equal "Magnus", value.name
    assert_equal "Programmer", value.bio
    assert_equal 4, value.karma
  end

  def test_merge
    form1 = form(
      name: fetch("name") | trim | required,
      bio: fetch("bio") | trim,
    )

    form2 = form(
      karma: fetch("karma") | trim | optional | number,
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

    step, path = result.step_errors[0]
    assert_equal [1], path
  end

  def test_inspect_errors
    form1 = form(
      name: fetch("name") | trim | required,
      bio: fetch("bio") | trim,
    )

    form2 = form(
      karma: fetch("karma") | trim | optional | number,
    )

    schema = form1 & form2

    result = schema.validate({"name" => "Magnus"})
    assert_equal 2, result.step_errors.size
    assert_equal 0, result.errors.steps.size
  end

  def test_nesteed_errors
    schema = for_each(form(username: fetch("username")))

    result = schema.validate([{}])
    assert result.error?

    assert_equal "0.username: must be present", result.error_messages[0]
  end

  def test_merging_errors
    schema = form(a: required) & form(a: required)

    assert_raises(ArgumentError) do
      schema.validate(nil)
    end
  end

  def test_duplicate_add_nested
    err1 = number.validate("abc")
    err2 = number.validate("abc")
    err3 = number.validate("abc")

    err1.add_nested(:key, err2)
    assert_raises(ArgumentError) do
      err1.add_nested(:key, err3)
    end
  end
end

