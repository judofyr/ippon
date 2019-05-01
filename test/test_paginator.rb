require_relative 'helper'

require 'ippon/paginator'

class TestPaginator < Minitest::Test
  include Ippon

  def test_basic
    p = Paginator.new(204, 20)
    assert_equal 1, p.first_page
    assert_equal 11, p.last_page

    # We're now at the first page
    assert_equal 1, p.current_page
    assert_nil p.prev_page
    assert_equal 2, p.next_page
    assert p.first_page?
    refute p.last_page?

    assert_equal 20, p.limit
    assert_equal 0, p.offset

    # Update to a middle page
    p.current_page = 5
    assert_equal 5, p.current_page
    assert_equal 4, p.prev_page
    assert_equal 6, p.next_page
    refute p.first_page?
    refute p.last_page?

    assert_equal 20, p.limit
    assert_equal 80, p.offset

    # Last page
    p.current_page = 11
    assert_equal 11, p.current_page
    assert_equal 10, p.prev_page
    assert_nil p.next_page
    refute p.first_page?
    assert p.last_page?

    assert_equal 20, p.limit
    assert_equal 200, p.offset

    # Check that clamping works
    p.current_page = -5
    assert_equal 1, p.current_page
    p.current_page = 15
    assert_equal 11, p.current_page

    # each_path
    seen_pages = []
    p.each_page do |num|
      seen_pages << num
    end
    assert_equal (1..11).to_a, seen_pages
  end
end


