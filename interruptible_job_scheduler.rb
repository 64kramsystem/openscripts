# Manages a background job, that is interrupted if a new job is scheduled.
#
# The provided job is executed in a forked process, and uses the writer passed by
# the user to write the result.
# If an existing job is running, it will be terminated, and its result discarded.
#
# The process strategy doesn't unfortunately work in all cases, therefore this
# class is more educational than general-purpose.
# Specifically, on a separate project I wrote (`pm-spotlight`), forked processes
# wouldn't terminate correctly (they wouldn't halt, and/or leave zombies) even
# in minimal scenarios (that is, with test code, without using this scheduler).
#
# This scheduler has been written in a rigorous concurrent programming way, and
# considers even unrealistic edge concurrent scenarios.
# It uses message passing for threads/processes communication, and terminates
# threads and processes in a controlled way.
#
# A buffer thread is used to ensure that writes to the provided writer are atomic,
# even in case an interruption signal is sent in the middle of a write; the suspect
# is that corner cases may leave the system buffer partially filled, and read()
# would succesfully read from it.
#
# Note that:
#
# 1. this case is actually extremely unlikely for the target use, but hey, threading
#    is not meant to be a walk in the park;
# 2. it's possible that this case may not happen at all, although it's not clear
#    from the IO documentation itself (it may also be platform-dependent).
#
# Example:
#
#   class SearchManager
#     def initialize(gui_writer)
#       @search_job_scheduler = InterruptibleJobScheduler.new
#       @gui_writer = gui_writer
#     end
#
#     def multithreaded_gui_start_search_event(search_pattern)
#       @search_job_scheduler.schedule(@gui_writer, 'SIGHUP') do
#         `find / -name #{search_pattern.shellescape}`
#       end
#     end
#   end
#
class InterruptibleJobScheduler
  # Commodore rulez
  BUFFER_WRITTEN = 0b01000000.chr
  PREVENT_TRANSFER = 0b10000000.chr
  JOB_PROCESS_COMPLETED = 0b00010100.chr

  def initialize
    @write_mutex = Mutex.new
  end

  # Threads entry point.
  #
  # Runs the provided block in a forked process, and sends the output to the provided
  # writer.
  # If the previous process is still running, it's terminated, and its output prevented
  # from being written to the writer.
  #
  # Termination is performed using the signal that is passed along with the
  # block to execute.
  #
  def schedule(external_result_writer, stop_signal, &block)
    @write_mutex.synchronize do
      if current_job_running?
        prevent_thread_transfer
        kill_current_job
      end

      # Both flags are actually a single event, but it's not possible to encapsulate all
      # in one, since it's IPC, so anyway, two concepts need to be used, one on the
      # process (pipe), and one in the thread (publisher to :current_job_running?).
      prevent_data_transfer_flag_reader, @prevent_data_transfer_flag_writer = IO.pipe
      @job_process_completed_flag_reader, job_process_completed_flag_writer = IO.pipe

      @current_job_stop_signal = stop_signal
      @current_job_pid = start_job_in_background(
        external_result_writer, prevent_data_transfer_flag_reader, job_process_completed_flag_writer, &block
      )
    end
  end

  private

  # We need to consider the theoretical case where the job thread takes a Very Long
  # Time™ between reading the result buffer and entering the critical block; if a
  # subsequent thread would take No Time™ for that, the slow thread would write after
  # the fast one.
  # All of this happens because the job process is a different concept from the thread
  # executing it; we need to deal with both.
  #
  def prevent_thread_transfer
    @prevent_data_transfer_flag_writer.write(PREVENT_TRANSFER)
    @prevent_data_transfer_flag_writer.close
  end

  def current_job_running?
    if @current_job_pid
      job_process_completed_flag = read_nonblock(@job_process_completed_flag_reader, JOB_PROCESS_COMPLETED.bytesize)

      job_process_completed_flag != JOB_PROCESS_COMPLETED
    end
  end

  def kill_current_job
    Process.kill(@current_job_stop_signal, -@current_job_pid)
  rescue Errno::ESRCH
    # There is an extremely small chance that the process finished between calling
    # current_job_running? and here, so we need to rescue that case.
  end

  # This method is arguably long; it's not been split into smaller methods because it's
  # extremely important to have an exact view of the workflow when considering concurrency.
  # Actually, a large part of it (~50%) is Ruby pipes boilerplate.
  #
  def start_job_in_background(external_result_writer, prevent_data_transfer_flag_reader, job_process_completed_flag_writer, &block)
    # Writers must be closed in the process not using them; if we don't, the EOF will
    # not be sent. We also close reader for cleanliness.
    child_process_pid_reader, child_process_pid_writer = IO.pipe

    Thread.new do
      buffer_written_flag_reader, buffer_written_flag_writer = IO.pipe
      result_buffer_reader, result_buffer_writer = IO.pipe

      fork do
        prevent_data_transfer_flag_reader.close
        child_process_pid_reader.close
        buffer_written_flag_reader.close
        result_buffer_reader.close

        Process.setsid

        child_process_pid_writer.write(Process.getpgrp)
        child_process_pid_writer.close

        job_result = block.call

        result_buffer_writer.write(job_result)
        result_buffer_writer.close

        buffer_written_flag_writer.write(BUFFER_WRITTEN)
        buffer_written_flag_writer.close

        job_process_completed_flag_writer.write(JOB_PROCESS_COMPLETED)
        job_process_completed_flag_writer.close
      end

      child_process_pid_writer.close
      buffer_written_flag_writer.close
      result_buffer_writer.close
      job_process_completed_flag_writer.close

      # If the forked process is interrupted, read() will return an empty string.
      # It's not possible to know with certainty whether result_buffer_writer has been
      # interrupted or not, since no error is raised when reading from an interrupted
      # forked process (an empty string is read).
      # The method :eof? works, but it's better not to rely on it until it's 100% clear
      # (see the class comment about the buffer).
      # In order to solve this problem, we use a second pipe.
      if buffer_written_flag_reader.read == BUFFER_WRITTEN
        job_result = result_buffer_reader.read

        @write_mutex.synchronize do
          prevent_data_transfer_flag = read_nonblock(prevent_data_transfer_flag_reader, PREVENT_TRANSFER.bytesize)

          if prevent_data_transfer_flag != PREVENT_TRANSFER
            external_result_writer.write(job_result)
            external_result_writer.flush
          end
        end
      end
    end

    child_process_pid = child_process_pid_reader.read.to_i

    # Detach it now; if we do it at kill time, we'll have a zombie until the next job
    # is submitted (and killing performed).
    Process.detach(child_process_pid)

    child_process_pid
  end

  def read_nonblock(reader, bytes_limit)
    reader.read_nonblock(bytes_limit)
  rescue IO::EAGAINWaitReadable
    # nothing to read!
  end
end
