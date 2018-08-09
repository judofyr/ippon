require_relative 'helper'

require 'ippon/validate'
require 'ippon/params'

class TestValidate < Minitest::Spec
  include Ippon::Validate

  def test_basic_field
    field = Schema.new("name")
      .fetch
      .trim
      .required

    result = field.validate({"name" => "  Magnus "})
    assert result.success?
    assert_equal "Magnus", result.value

    result = field.validate({"name" => "   "})
    assert result.error?
  end

  def test_helpers
    field = Schema.new("name")
      .fetch
      .trim
      .required
      .integer
      .boolean
      .match(/\w+/, description: "foo")
      .match_with(description: "bar") { |obj| obj }

    assert_instance_of Steps::Fetch, field.steps[0]
    assert_equal "name", field.steps[0].props[:key]
    assert_instance_of Steps::Trim, field.steps[1]
    assert_instance_of Steps::Required, field.steps[2]
    assert_instance_of Steps::Integer, field.steps[3]
    assert_instance_of Steps::Boolean, field.steps[4]

    assert_instance_of Steps::Match, field.steps[5]
    assert_equal(/\w+/, field.steps[5].props[:predicate])
    assert_equal("foo", field.steps[5].props[:description])

    assert_instance_of Steps::Match, field.steps[6]
    assert_instance_of Proc, field.steps[6].props[:predicate]
    assert_equal 123, field.steps[6].props[:predicate].call(123)
    assert_equal "bar", field.steps[6].props[:description]
  end

  ## Testing the Steps directly

  def process(step, value)
    result = Result.new(value)
    step.process(result)
    result
  end

  def process_value(step, value)
    result = process(step, value)
    assert result.success?
    result.value
  end

  def test_fetch
    fetch = Steps::Fetch.new(key: "name")

    assert_equal "Magnus", process_value(fetch, {"name" => "Magnus"})

    # Custom object
    obj = Object.new
    def obj.[](key)
      key.upcase
    end

    assert_equal "NAME", process_value(fetch, obj)
  end

  def test_trim
    trim = Steps::Trim.new

    assert_equal "123", process_value(trim, "123")
    assert_equal "123", process_value(trim, "  123  ")
    assert_equal "1 2 3", process_value(trim, "  1 2 3  ")
    assert_nil process_value(trim, "\t  \t ")
  end

  def test_optional
    optional = Steps::Optional.new

    result = process(optional, "123")
    refute result.halted?

    result = process(optional, "")
    refute result.halted?

    result = process(optional, nil)
    assert result.halted?
  end

  def test_integer
    integer = Steps::Integer.new

    assert_equal 123, process_value(integer, "123")
    assert_equal -123, process_value(integer, "-123")
    assert_equal 123, process_value(integer, "+123")

    result = process(integer, "  123  ")
    assert result.error?
  end

  def test_boolean
    boolean = Steps::Boolean.new

    assert_equal false, process_value(boolean, nil)
    assert_equal false, process_value(boolean, false)
    assert_equal true, process_value(boolean, "")
    assert_equal true, process_value(boolean, "1")
    assert_equal true, process_value(boolean, "false")
  end

  def test_match
    match = Steps::Match.new(predicate: 123)

    assert_equal 123, process_value(match, 123)
    result = process(match, 124)
    assert result.error?

    obj = Object.new
    def obj.===(other)
      (other % 2) == 0
    end
    match = Steps::Match.new(predicate: obj)

    assert_equal 124, process_value(match, 124)
    result = process(match, 125)
    assert result.error?
  end

  def test_form
    form = Steps::Form.new(fields: { name: Schema.new("karma").fetch.integer })

    assert_equal({ name: 123 }, process_value(form, { "karma" => "123" }))

    result = process(form, { "karma" => " 123" })
    assert result.error?
    assert result.halted?
  end

  ## Forms

  def test_basic_form
    form = Schema.new("user")
      .form(
        name: Schema.new("name").fetch.trim.required,
        bio: Schema.new("bio").fetch.trim,
        karma: Schema.new("karma").fetch.trim.optional.integer,
      )

    result = form.validate(
      "name" => "Magnus",
      "bio" => "Programmer  ",
      "karma" => " 4"
    )

    assert result.success?
    assert_equal({name: "Magnus", bio: "Programmer", karma: 4}, result.value)

    result = form.validate(
      "name" => "  ",
      "bio" => "Programmer  ",
      "karma" => " abc"
    )
    assert result.error?
    assert_equal 2, result.errors.size
  end

  def test_form_with_more_steps
    form = Schema.new("user")
      .form(
        password: Schema.new("password").fetch.trim,
        password_confirm: Schema.new("password_confirm").fetch.trim,
      )
      .match_with { |value|
        if value[:password]
          value[:password] == value[:password_confirm]
        else
          true
        end
      }

    result = form.validate({})
    assert result.success?

    result = form.validate({"password" => "123", "password_confirm" => "123"})
    assert result.success?

    result = form.validate({"password" => "123", "password_confirm" => "12"})
    assert result.error?
  end

  ## Lists

  def test_lists
    field = Schema.new("nums")
      .fetch_many
      .for_each(Schema.new.integer)

    params = Ippon::Params::URLEncoded.new("nums=1&nums=2")

    result = field.validate(params)
    assert result.success?
    assert_equal [1, 2], result.value

    params = Ippon::Params::URLEncoded.new("nums=%201&nums=2")

    result = field.validate(params)
    assert result.error?
    assert_equal [" 1", 2], result.value
  end
end

