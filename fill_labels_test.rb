#!/usr/bin/env ruby
require 'minitest/autorun'
require 'tty-prompt'

# `fill_labels` has no `.rb` extension, so `require_relative` won't find it.
# `load` accepts an arbitrary filename. The script's `if __FILE__ == $PROGRAM_NAME`
# block doesn't fire because this test file is the program being run.
load File.expand_path('fill_labels', __dir__)

class FillLabelsDecodePositionsTest < Minitest::Test
  def test_single_digit
    assert_equal ["3"], FillLabels.new.send(:decode_label_positions, "3")
  end

  def test_comma_separated_list
    assert_equal ["1", "3", "5"], FillLabels.new.send(:decode_label_positions, "1,3,5")
  end

  def test_range
    assert_equal (3..7), FillLabels.new.send(:decode_label_positions, "3-7")
  end

  # ── Invalid inputs raise ─────────────────────────────────────────────────

  def test_non_numeric_raises
    assert_raises(RuntimeError) { FillLabels.new.send(:decode_label_positions, "abc") }
  end

  def test_empty_raises
    assert_raises(RuntimeError) { FillLabels.new.send(:decode_label_positions, "") }
  end

  def test_trailing_comma_raises
    assert_raises(RuntimeError) { FillLabels.new.send(:decode_label_positions, "1,2,") }
  end

  def test_open_range_raises
    assert_raises(RuntimeError) { FillLabels.new.send(:decode_label_positions, "3-") }
  end
end

class FillLabelsCheckAddressesTest < Minitest::Test
  def test_valid_addresses_pass
    FillLabels.new.send(:check_addresses!, %w[a b c], %w[w x y z])
  end

  def test_minimal_addresses_pass
    FillLabels.new.send(:check_addresses!, %w[a], %w[b])
  end

  def test_oversized_sender_raises
    e = assert_raises(RuntimeError) { FillLabels.new.send(:check_addresses!, %w[a b c d], %w[w]) }
    assert_match(/sender/i, e.message)
  end

  def test_oversized_recipient_raises
    e = assert_raises(RuntimeError) { FillLabels.new.send(:check_addresses!, %w[a], %w[v w x y z]) }
    assert_match(/recipient/i, e.message)
  end
end

class FillLabelsPrepareReplacementsTest < Minitest::Test
  def test_fills_keys_for_single_position
    r = FillLabels.new.send(:prepare_template_replacements, %w[S0 S1], %w[R0 R1], ["3"])
    assert_equal "S0", r["sender_line_0_3"]
    assert_equal "S1", r["sender_line_1_3"]
    assert_equal "R0", r["recipient_line_0_3"]
    assert_equal "R1", r["recipient_line_1_3"]
  end

  def test_fills_keys_for_multiple_positions
    r = FillLabels.new.send(:prepare_template_replacements, %w[S0], %w[R0], ["1", "2"])
    assert_equal "S0", r["sender_line_0_1"]
    assert_equal "S0", r["sender_line_0_2"]
    assert_equal "R0", r["recipient_line_0_1"]
    assert_equal "R0", r["recipient_line_0_2"]
  end

  def test_includes_catch_all_regex_for_unfilled_placeholders
    r = FillLabels.new.send(:prepare_template_replacements, %w[S], %w[R], ["0"])
    regex_key = r.keys.find { |k| k.is_a?(Regexp) }
    refute_nil regex_key
    assert_equal '', r[regex_key]
    assert_match regex_key, "sender_line_0_5"
    assert_match regex_key, "recipient_line_3_9"
  end
end

class FillLabelsCompileTemplateTest < Minitest::Test
  def test_substitutes_simple_placeholder
    out = FillLabels.new.send(:compile_template, "Hi {{name}}!", { "name" => "Donald" })
    assert_equal "Hi Donald!", out
  end

  def test_html_escapes_values
    out = FillLabels.new.send(:compile_template, "{{x}}", { "x" => "A & B <c>" })
    assert_equal "A &amp; B &lt;c&gt;", out
  end

  def test_substitutes_multiple_placeholders
    out = FillLabels.new.send(:compile_template, "{{a}}-{{b}}", { "a" => "1", "b" => "2" })
    assert_equal "1-2", out
  end

  def test_regex_key_replaces_remaining_placeholders
    template = "{{sender_line_0_5}}/{{recipient_line_1_8}}/keep"
    replacements = { /(sender|recipient)_line_\d_\d/ => '' }
    out = FillLabels.new.send(:compile_template, template, replacements)
    assert_equal "//keep", out
  end

  def test_unmatched_placeholder_is_left_intact
    out = FillLabels.new.send(:compile_template, "{{missing}}", { "other" => "x" })
    assert_equal "{{missing}}", out
  end
end

class ConfigurationPreparerFindRecipientTest < Minitest::Test
  def setup
    @book = {
      "scrooge" => ["Scrooge McDuck", "McDuck Manor", "Duckburg", "Calisota"],
      "homer"   => ["Homer Simpson", "742 Evergreen Terrace", "Springfield"],
    }
  end

  def test_pattern_matches_book_key
    out = ConfigurationPreparer.new.send(:find_recipient_address, "scrooge", @book)
    assert_equal @book["scrooge"], out
  end

  def test_pattern_matches_first_address_line
    out = ConfigurationPreparer.new.send(:find_recipient_address, "homer simpson", @book)
    assert_equal @book["homer"], out
  end

  def test_pattern_is_case_insensitive
    out = ConfigurationPreparer.new.send(:find_recipient_address, "SCROOGE", @book)
    assert_equal @book["scrooge"], out
  end

  def test_partial_pattern_matches
    out = ConfigurationPreparer.new.send(:find_recipient_address, "homer", @book)
    assert_equal @book["homer"], out
  end

  def test_no_match_raises
    assert_raises(RuntimeError) { ConfigurationPreparer.new.send(:find_recipient_address, "nobody", @book) }
  end

  def test_multiline_input_returned_as_is_without_lookup
    raw = "Manual Name\nLine 2\nLine 3"
    out = ConfigurationPreparer.new.send(:find_recipient_address, raw, @book)
    assert_equal ["Manual Name", "Line 2", "Line 3"], out
  end

  def test_multiple_matches_prompt_user_to_pick
    book = @book.merge("scrooger_jr" => ["Scrooge Junior", "Other Manor", "Duckburg"])
    captured = nil
    fake_prompt = Object.new
    fake_prompt.define_singleton_method(:select) do |_msg, choices, **|
      captured = choices
      choices.values.last
    end
    original_new = TTY::Prompt.method(:new)
    TTY::Prompt.define_singleton_method(:new) { fake_prompt }
    begin
      out = ConfigurationPreparer.new.send(:find_recipient_address, "scrooge", book)
      assert_equal book["scrooger_jr"], out
    ensure
      TTY::Prompt.define_singleton_method(:new, &original_new)
    end
    assert_equal 2, captured.size
    assert(captured.keys.any? { |k| k.start_with?("scrooge:") })
    assert(captured.keys.any? { |k| k.start_with?("scrooger_jr:") })
  end
end

class FillLabelsModeDetectionTest < Minitest::Test
  def test_newline_in_input_means_address_mode
    assert_equal :address, FillLabels.new.send(:detect_mode, "Foo\nBar")
  end

  def test_dot_in_input_means_image_mode
    assert_equal :image, FillLabels.new.send(:detect_mode, "/tmp/foo.png")
  end

  def test_no_dot_no_newline_means_address_mode
    assert_equal :address, FillLabels.new.send(:detect_mode, "scrooge")
  end
end

class FillLabelsStripFramesTest < Minitest::Test
  def test_keeps_selected_frames_unwraps_markers
    template = "<!--FRAME_0--><draw:image href='X'/><!--/FRAME_0-->" \
               "<!--FRAME_1--><draw:image href='Y'/><!--/FRAME_1-->"
    out = FillLabels.new.send(:strip_unselected_frames, template, [0])
    assert_includes out, "<draw:image href='X'/>"
    refute_includes out, "<draw:image href='Y'/>"
    refute_includes out, "FRAME_0"
    refute_includes out, "FRAME_1"
  end

  def test_strips_inner_content_of_unselected_frames
    template = "<!--FRAME_0-->IN<!--/FRAME_0--><!--FRAME_3-->X<!--/FRAME_3-->"
    out = FillLabels.new.send(:strip_unselected_frames, template, [3])
    refute_includes out, "IN"
    assert_includes out, "X"
  end

  # Empty as-char draw:frame elements collapse to zero width in LibreOffice and
  # would shift the image-bearing frame into position 0; the placeholder keeps
  # unselected frames at their declared size.
  #
  def test_unselected_frames_receive_size_preserving_placeholder
    template = "<!--FRAME_0--><draw:image href='X'/><!--/FRAME_0-->" \
               "<!--FRAME_1--><draw:image href='Y'/><!--/FRAME_1-->"
    out = FillLabels.new.send(:strip_unselected_frames, template, [1])
    assert_includes out, '<draw:text-box>'
    refute_match(/<draw:image href='X'\/>/, out)
  end
end

class FillLabelsBestFitRotationTest < Minitest::Test
  def setup
    @format = { template: "topstick_8739", type: "image", cols: 2, rows: 4, cell_width_mm: 96.5, cell_height_mm: 67.7 }
    @png    = "/tmp/fill_labels_rotation_test_#{Process.pid}.png"
  end

  def teardown
    File.delete(@png) if File.exist?(@png)
  end

  def write_png(width, height)
    File.open(@png, 'wb') do |f|
      f.write("\x89PNG\r\n\x1a\n".b)
      f.write([13].pack('N')) ; f.write("IHDR".b)
      f.write([width, height, 8, 2, 0, 0, 0].pack('NNCCCCC'))
      f.write([0].pack('N')) # bogus CRC; png_dimensions doesn't validate it
    end
  end

  def test_png_dimensions_reads_width_and_height
    write_png(640, 480)
    assert_equal [640, 480], FillLabels.new.send(:png_dimensions, @png)
  end

  def test_landscape_image_into_landscape_cell_stays_upright
    write_png(1000, 500)
    assert_equal 0, FillLabels.new.send(:best_fit_rotation_degrees, @png, @format)
  end

  def test_portrait_image_into_landscape_cell_rotates_90
    write_png(500, 1000)
    assert_equal 90, FillLabels.new.send(:best_fit_rotation_degrees, @png, @format)
  end

  def test_square_image_keeps_zero_rotation
    write_png(800, 800)
    assert_equal 0, FillLabels.new.send(:best_fit_rotation_degrees, @png, @format)
  end
end

class FillLabelsCheckImagePositionsTest < Minitest::Test
  def setup
    @format = { template: "topstick_8739", type: "image", cols: 2, rows: 4 }
  end

  def test_in_range_positions_pass
    FillLabels.new.send(:check_image_positions!, [0, 3, 7], @format)
    FillLabels.new.send(:check_image_positions!, (0..7), @format)
  end

  def test_out_of_range_position_raises
    e = assert_raises(RuntimeError) { FillLabels.new.send(:check_image_positions!, [8], @format) }
    assert_match(/out of range/i, e.message)
    assert_match(/0-7/,            e.message)
  end

  def test_out_of_range_in_range_raises
    e = assert_raises(RuntimeError) { FillLabels.new.send(:check_image_positions!, (0..8), @format) }
    assert_match(/8/, e.message)
  end
end

class FillLabelsEnsureCleanupTest < Minitest::Test
  def test_invalid_position_surfaces_original_error_not_cleanup_enoent
    format = { template: "labelwonderland_es0010", type: "address" }
    e = assert_raises(RuntimeError) do
      FillLabels.new.fill(%w[S], %w[R], "abc", format)
    end
    assert_match(/Unrecognized label position/, e.message)
  end
end

class ConfigurationPreparerLoadConfigTest < Minitest::Test
  def setup
    @config_path = "/tmp/fill_labels_test_#{Process.pid}.ini"
    File.write(@config_path, <<~INI)
      [defaults]
      address = labelwonderland_es0010
      image   = topstick_8739
      sender  = Donald Duck:1313 Webfoot Walk:Duckburg

      [format.labelwonderland_es0010]
      type          = address
      template      = labelwonderland_es0010
      next_position = 5

      [format.topstick_8739]
      type           = image
      template       = topstick_8739
      cols           = 2
      rows           = 4
      cell_width_mm  = 96.5
      cell_height_mm = 67.7

      [address_book]
      scrooge = Scrooge McDuck:McDuck Manor:Duckburg:Calisota
      homer   = Homer Simpson:742 Evergreen Terrace:Springfield
    INI
  end

  def teardown
    File.delete(@config_path) if File.exist?(@config_path)
  end

  def test_loads_defaults
    cfg = ConfigurationPreparer.new.send(:load_config, @config_path)
    assert_equal "labelwonderland_es0010", cfg.fetch(:defaults).fetch(:address)
    assert_equal "topstick_8739",          cfg.fetch(:defaults).fetch(:image)
  end

  def test_loads_sender_from_defaults
    cfg = ConfigurationPreparer.new.send(:load_config, @config_path)
    assert_equal ["Donald Duck", "1313 Webfoot Walk", "Duckburg"], cfg.fetch(:sender)
  end

  def test_loads_formats_keyed_by_name
    cfg = ConfigurationPreparer.new.send(:load_config, @config_path)
    addr = cfg.fetch(:formats).fetch("labelwonderland_es0010")
    assert_equal "address",                addr.fetch(:type)
    assert_equal "labelwonderland_es0010", addr.fetch(:template)

    img = cfg.fetch(:formats).fetch("topstick_8739")
    assert_equal "image",         img.fetch(:type)
    assert_equal "topstick_8739", img.fetch(:template)
    assert_equal 2,               img.fetch(:cols)
    assert_equal 4,               img.fetch(:rows)
    assert_in_delta 96.5,         img.fetch(:cell_width_mm),  0.001
    assert_in_delta 67.7,         img.fetch(:cell_height_mm), 0.001
  end

  def test_loads_address_book_as_split_lines
    cfg = ConfigurationPreparer.new.send(:load_config, @config_path)
    book = cfg.fetch(:address_book)
    assert_equal ["Scrooge McDuck", "McDuck Manor", "Duckburg", "Calisota"], book["scrooge"]
    assert_equal ["Homer Simpson", "742 Evergreen Terrace", "Springfield"],   book["homer"]
  end

  def test_loads_next_position_as_int_when_present
    cfg = ConfigurationPreparer.new.send(:load_config, @config_path)
    assert_equal 5, cfg.fetch(:formats).fetch("labelwonderland_es0010").fetch(:next_position)
  end

  def test_next_position_absent_when_not_in_config
    cfg = ConfigurationPreparer.new.send(:load_config, @config_path)
    refute cfg.fetch(:formats).fetch("topstick_8739").key?(:next_position)
  end
end

class ConfigurationPreparerUpdateConfigValueTest < Minitest::Test
  def setup
    @config_path = "/tmp/fill_labels_update_test_#{Process.pid}.ini"
  end

  def teardown
    File.delete(@config_path) if File.exist?(@config_path)
  end

  def test_updates_existing_key_preserving_alignment
    File.write(@config_path, <<~INI)
      [format.topstick_8739]
      type           = image
      template       = topstick_8739
      next_position  = 0
    INI

    ConfigurationPreparer.new.send(:update_config_value, @config_path, "format.topstick_8739", "next_position", 4)

    assert_equal <<~INI, File.read(@config_path)
      [format.topstick_8739]
      type           = image
      template       = topstick_8739
      next_position  = 4
    INI
  end

  def test_inserts_key_when_missing_keeping_neighbouring_sections_intact
    File.write(@config_path, <<~INI)
      [format.topstick_8739]
      type     = image
      template = topstick_8739

      [address_book]
      scrooge = Scrooge McDuck:McDuck Manor:Duckburg
    INI

    ConfigurationPreparer.new.send(:update_config_value, @config_path, "format.topstick_8739", "next_position", 2)

    assert_equal <<~INI, File.read(@config_path)
      [format.topstick_8739]
      type     = image
      template = topstick_8739
      next_position = 2

      [address_book]
      scrooge = Scrooge McDuck:McDuck Manor:Duckburg
    INI
  end

  def test_inserts_key_at_eof_when_section_is_last
    File.write(@config_path, <<~INI)
      [format.topstick_8739]
      type     = image
      template = topstick_8739
    INI

    ConfigurationPreparer.new.send(:update_config_value, @config_path, "format.topstick_8739", "next_position", 7)

    assert_equal <<~INI, File.read(@config_path)
      [format.topstick_8739]
      type     = image
      template = topstick_8739
      next_position = 7
    INI
  end

  def test_raises_when_section_missing
    File.write(@config_path, "[other]\nx = 1\n")
    assert_raises(RuntimeError) do
      ConfigurationPreparer.new.send(:update_config_value, @config_path, "format.missing", "next_position", 0)
    end
  end
end

class ConfigurationPreparerSaveNextPositionTest < Minitest::Test
  def setup
    @config_path = "/tmp/fill_labels_save_next_test_#{Process.pid}.ini"
    File.write(@config_path, <<~INI)
      [format.topstick_8739]
      type          = image
      template      = topstick_8739
      next_position = 0
    INI
  end

  def teardown
    File.delete(@config_path) if File.exist?(@config_path)
  end

  def test_single_position_increments_by_one
    ConfigurationPreparer.new.save_next_position("topstick_8739", "3", path: @config_path)
    assert_match(/next_position = 4/, File.read(@config_path))
  end

  def test_range_advances_past_highest_used
    ConfigurationPreparer.new.save_next_position("topstick_8739", "3-7", path: @config_path)
    assert_match(/next_position = 8/, File.read(@config_path))
  end

  def test_comma_list_advances_past_highest_used
    ConfigurationPreparer.new.save_next_position("topstick_8739", "1,3,5", path: @config_path)
    assert_match(/next_position = 6/, File.read(@config_path))
  end
end
