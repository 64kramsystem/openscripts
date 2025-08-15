module Progress
  struct Theme
    getter complete : String
    getter alt_progress_head : String?
    getter progress_head : String?
    getter incomplete : String
    getter bar_start : String
    getter bar_end : String
    getter width : Int32
    getter number_format : String
    getter binary_prefix_format : Int::BinaryPrefixFormat
    getter decimal_separator : String

    def initialize(@complete = "\u2593", @alt_progress_head = nil,
                   @progress_head = nil, @incomplete = "\u2591",
                   @bar_start = "[", @bar_end = "]", @width = 60,
                   @number_format = "%.1f%%", @binary_prefix_format = :JEDEC,
                   @decimal_separator = ".")

      if has_progress_head? && @alt_progress_head == nil
        @alt_progress_head = @progress_head
      end
    end

    def has_progress_head?
      !progress_head.nil?
    end
  end
end
