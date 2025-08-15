require "./theme"

module Progress
  class Renderer
    @theme : Progress::Theme

    property throughput : Float64

    def initialize(@bar : Progress::Bar)
      @theme = @bar.theme
      @head_pos = 1
      @throughput = 0
      @start_time = Time.monotonic
    end

    def print
      @bar.output_stream.flush
      @bar.output_stream.print("#{render_progress_bar} #{summary} \r")
      @bar.output_stream.flush
      @bar.output_stream.print("\n") if @bar.done?
    end

    def summary
      if @bar.is_a?(IOBar)
        "#{formatted_percentage} (#{io_summary}, #{render_throughput}) [#{render_elapsed_time}:#{render_eta_time}]"
      else
        formatted_percentage
      end
    end

    def percent_complete
      @bar.current.to_f / (@bar.total.to_f / 100.to_f)
    end

    private def render_throughput
      "#{@throughput.to_u64.humanize_bytes(format: @theme.binary_prefix_format)}/s"
    end

    private def render_elapsed_time
      "#{render_time(Time.monotonic - @start_time)}"
    end

    private def render_eta_time
      if @throughput > 0
        eta_seconds = (@bar.remaining/@throughput).to_u64
        render_time(Time::Span.new(seconds: eta_seconds))
      else
        "∞"
      end
    end

    private def render_time(time_span : Time::Span)
      hours = time_span.hours
      minutes = time_span.minutes
      seconds = time_span.seconds

      time_string = ""

      if hours > 0
        time_string += "#{hours}h"
      end

      if minutes > 0
        time_string += "#{minutes}m"
      end

      time_string += "#{seconds}s"

      time_string
    end

    private def io_summary
      "#{@bar.humanized_current}/#{@bar.humanized_total}"
    end

    private def formatted_percentage
      sprintf(@theme.number_format, percent_complete)
    end

    private def render_progress_bar
      "#{@theme.bar_start}#{render_progress}#{@theme.bar_end}"
    end

    private def incomplete_segment
      "#{@theme.incomplete * (@theme.width - position)}"
    end

    private def completed_segment
      "#{@theme.complete * position}"
    end

    private def render_progress_head
      if @bar.done?
        return nil
      end

      marker = @head_pos > 0 ? @theme.progress_head : @theme.alt_progress_head
      @head_pos *= -1
      marker
    end

    private def render_progress
      if @theme.has_progress_head?
        "#{completed_segment}#{render_progress_head}#{incomplete_segment}"
      else
        "#{completed_segment}#{incomplete_segment}"
      end
    end

    private def position
      ((@bar.current.to_f * @theme.width.to_f) / @bar.total).to_i
    end
  end
end
