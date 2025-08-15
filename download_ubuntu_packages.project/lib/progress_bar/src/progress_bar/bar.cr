require "./theme"
require "./renderer"

module Progress
  class Bar
    alias Num = UInt64 | UInt32 | Int64 | Int32

    getter current, total, theme, output_stream

    def initialize(@total = 100, @step = 1, @theme = Theme.new,
                   @output_stream = STDOUT)

      @current = 0.0_f64
      @current_tick = 0
      @lock = Mutex.new
      @renderer = Renderer.new(bar: self)
    end

    def tick(n = @step, no_print = false)
      @lock.synchronize do
        previous_value = @current
        @current += n
        @current = @current.clamp(0.0_f64, @total)
        unless @current == previous_value || no_print
          @renderer.not_nil!.print
        end
      end
    end

    def finish!
      @lock.synchronize do
        @current = @total
        @renderer.not_nil!.print
      end
    end

    def done?
      current >= total
    end

    def remaining
      total - current
    end

    def humanized_total
      total.to_u64.humanize_bytes(
        precision: 1,
        significant: false,
        separator: @theme.decimal_separator,
        format: @theme.binary_prefix_format
      )
    end

    def humanized_current
      current.to_u64.humanize_bytes(
        precision: 1,
        significant: false,
        separator: @theme.decimal_separator,
        format: @theme.binary_prefix_format
      )
    end
  end
end
