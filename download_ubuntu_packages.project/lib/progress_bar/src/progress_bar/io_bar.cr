require "./bar"
require "./io_writer"

module Progress
  class IOBar < Bar
    ONE_SECOND = Time::Span.new(seconds: 1)

    def initialize(@total = 100, @step = 1, @theme = Theme.new,
                   @output_stream = STDOUT, @lock = Mutex.new)

      @current = 0.0_f64
      @current_tick = 0
      @last_tick_at = Time.monotonic
      @bytes_written = 0_u64
      @throughput_lock = Mutex.new
      @renderer = Renderer.new(bar: self)
      @progress_writer = IOWriter.new(bar: self)
    end

    def progress_writer
      @progress_writer.not_nil!
    end

    # Returns the throughput, in bytes per second.
    # Also resets the last tick to the current time
    def caclulate_throughput(bytesize)
      @throughput_lock.synchronize do
        delta = Time.monotonic - @last_tick_at
        @bytes_written += bytesize
        if delta >= ONE_SECOND
          @last_tick_at = Time.monotonic
          @renderer.not_nil!.throughput = @bytes_written/delta.to_f
          @bytes_written = 0
        end
      end
    end
  end
end
