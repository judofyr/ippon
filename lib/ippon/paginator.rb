module Ippon
  # Paginator represents a pagination of a collection. You initiailize it with
  # the total number of entries, how many entries you want per page, and the
  # current page, and it provides various helpers for working with pages.
  #
  # @example Using {#limit} and {#offset} to build the correct query.
  #   all_rows = User.where(is_active: true)
  #
  #   entries_per_page = 20
  #   total_entries = all_rows.count
  #   current_page = params[:page].to_i
  #   paginator = Paginator.new(total_entries, entries_per_page, current_page)
  #
  #   rows = all_rows.limit(paginator.limit).offset(paginator.offset)
  #
  # @example Using Paginator with {Tubby}[https://github.com/judofyr/tubby] to render a Bootstrap pagination
  #   class BootstrapPagination < Struct.new(:paginator, :url)
  #     def url_for(page)
  #       "#{url}&page=#{page}"
  #     end
  #
  #     def item(t, page, text, is_active = false)
  #       t.li(class: 'page-item', disabled: !page, active: is_active) {
  #         if page
  #           t.a(text, href: url_for(page), class: 'page-link')
  #         else
  #           t.span(text, class: 'page-link')
  #         end
  #       }
  #     end
  #
  #     def to_tubby
  #       Tubby.new { |t|
  #         t.nav {
  #           t.ul(class: "pagination") {
  #             item(t, paginator.prev_page, "Previous")
  #
  #             paginator.each_page do |page|
  #               item(t, page, page.to_s, paginator.current_page == page)
  #             end
  #
  #             item(t, paginator.next_page, "Next")
  #           }
  #         }
  #       }
  #     end
  #   end
  class Paginator
    # The total number of entries.
    attr_reader :total_entries

    # The number of entries per page. This method is aliased as {#limit} to
    # complement {#offset}.
    attr_reader :entries_per_page

    # The current page number. This value is always guaranteed to be within
    # {#first_page} and {#last_page}.
    attr_reader :current_page

    def initialize(total_entries, entries_per_page, current_page = 1)
      @total_entries = total_entries
      @entries_per_page = entries_per_page
      self.current_page = current_page
    end

    # Updates the current page number. This method will clamp the value to
    # between {#first_page} and {#last_page}:
    #
    #   p = Paginator.new(50, 10)
    #   p.current_page = 60
    #   p.current_page # => 5
    # 
    # @param new_value [Integer] the new page number.
    def current_page=(new_value)
      @current_page = new_value.clamp(first_page, last_page)
    end

    # This always returns 1, but is provided to complement {#last_page}.
    #
    # @return [Integer] the page number of the first page.
    def first_page
      1
    end

    # @return [Boolean] true if the paginator is currently on the first page.
    def first_page?
      current_page == first_page
    end

    # @return [Integer] the page number of the last page.
    def last_page
      @last_page ||= [(total_entries / entries_per_page.to_f).ceil, first_page].max
    end

    # @return [Boolean] true if the paginator is currently on the last page.
    def last_page?
      current_page == last_page
    end

    # @return [Integer, nil] the page number of the previous page (if it exists).
    def prev_page
      current_page - 1 unless first_page?
    end

    # @return [Integer, nil] the page number of the next page (if it exists).
    def next_page
      current_page + 1 unless last_page?
    end

    # @yield every page number (from 1 to the last page).
    # @yieldparam [String] num page number.
    def each_page(&blk)
      (first_page .. last_page).each(&blk)
    end

    alias limit entries_per_page

    # Calculates the number of entries you need to skip in order to reach the
    # current page.
    #
    # @return [Integer]
    def offset
      (current_page - 1) * entries_per_page
    end
  end
end

