#!/usr/bin/env ruby
require 'minitest/autorun'

load File.expand_path('set_song_bpms', __dir__)

class SetSongBpmsTest < Minitest::Test
  def setup
    @script = SetSongBpms.new
  end

  def beats_from(intervals)
    intervals.each_with_object([0.0]) { |interval, beats| beats << beats.last + interval }
  end

  # ── format_comment ───────────────────────────────────────────────────────

  def test_format_comment_pads_to_three_digits
    assert_equal 'BPM=098', @script.format_comment([98])
  end

  def test_format_comment_two_tempos_max_first_both_padded
    assert_equal 'BPM=236/115', @script.format_comment([236, 115])
    assert_equal 'BPM=098/049', @script.format_comment([98, 49])
  end

  # ── bpms ─────────────────────────────────────────────────────────────────

  def test_bpms_constant_tempo
    assert_equal [120], @script.bpms(beats_from([0.5] * 100))
  end

  def test_bpms_ignores_break_outliers
    intervals = [0.4] * 100 + [0.8] * 5 + [0.4] * 100
    assert_equal [150], @script.bpms(beats_from(intervals))
  end

  def test_bpms_recovers_true_tempo_from_frame_quantized_beats
    true_interval = 0.413 # 145.28 BPM
    beats = (0..200).map { |i| (i * true_interval / 0.02).round * 0.02 }
    assert_equal [145], @script.bpms(beats)
  end

  def test_bpms_detects_sustained_tempo_change
    intervals = [0.52] * 100 + [0.2542] * 150 # 115.4 BPM then 236.0 BPM
    assert_equal [236, 115], @script.bpms(beats_from(intervals))
  end

  def test_bpms_mild_drift_reports_single_dominant_tempo
    intervals = [0.4] * 140 + [0.34] * 60 # ratio 1.18, below the section threshold
    assert_equal [150], @script.bpms(beats_from(intervals))
  end

  def test_bpms_too_few_beats_returns_empty
    assert_equal [], @script.bpms([0.0, 0.5])
  end

  # ── dominant_bpm ─────────────────────────────────────────────────────────

  def test_dominant_bpm_of_two_tempo_song_is_the_longer_section
    intervals = [0.52] * 100 + [0.2542] * 150
    assert_equal 236, @script.dominant_bpm(beats_from(intervals))
  end

  # ── worker_count ─────────────────────────────────────────────────────────

  def test_worker_count_cpu_uses_quarter_of_cores_capped_at_seven
    assert_equal 7, @script.worker_count('cpu', 32)
    assert_equal 2, @script.worker_count('cpu', 10)
    assert_equal 1, @script.worker_count('cpu', 2)
  end

  def test_worker_count_gpu
    assert_equal 4, @script.worker_count('cuda', 32)
    assert_equal 2, @script.worker_count('mps', 10)
  end

  # ── tag_command ──────────────────────────────────────────────────────────

  def test_tag_command_darwin_uses_homebrew_kid3
    assert_equal ['/opt/homebrew/bin/kid3-cli', '-c', "set comment 'BPM=098'", 'a.mp3'],
                 @script.tag_command('a.mp3', 'BPM=098', darwin: true)
  end

  def test_tag_command_linux_mp3_uses_eyed3
    assert_equal ['eyeD3', '--remove-all-comments', '--comment', 'BPM=142', 'a.mp3'],
                 @script.tag_command('a.mp3', 'BPM=142', darwin: false)
  end

  def test_tag_command_linux_m4a_uses_system_python_mutagen
    assert_equal ['/usr/bin/python3', '-c', SetSongBpms::TAG_PYTHON, 'b.m4a', 'BPM=236/115'],
                 @script.tag_command('b.m4a', 'BPM=236/115', darwin: false)
  end
end
