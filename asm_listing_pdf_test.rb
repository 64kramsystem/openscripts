#!/usr/bin/env ruby

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class AsmListingPdfTest < Minitest::Test
  DEFAULT_COLUMNS = 129

  def setup
    @directory = Dir.mktmpdir('asm_listing_pdf_test')
    @bin = File.join(@directory, 'bin')
    FileUtils.mkdir(@bin)
    File.write(File.join(@bin, 'pdflatex'), <<~'SH')
      #!/usr/bin/env bash
      cp listing.asm "$ASM_LISTING_PDF_CAPTURE"
      : > listing.pdf
    SH
    FileUtils.chmod(0755, File.join(@bin, 'pdflatex'))
    File.write(File.join(@bin, 'getopt'), <<~'SH')
      #!/usr/bin/env bash
      while [[ $1 != -- ]]; do shift; done
      shift
      printf " -- %q\n" "$1"
    SH
    FileUtils.chmod(0755, File.join(@bin, 'getopt'))
  end

  def teardown
    FileUtils.rm_rf(@directory)
  end

  def test_links_xrefs_symbols_and_qualified_addresses_without_changing_listing_bytes
    source = <<~'ASM'.b
      entry:
        0000:0100       90                        NOP
      XREF[2]: 0000:0100(j), missing_overlay::0000:0100(j)
                      ; Exact phase reference: resident::000001
      Note: plain prose
      target:
      resident::000001 90                        NOP
      resident::000001 90                        NOP
                      ; XREF[2]: resident::000001(RW), resident::000001(t)
      offcut.name:    ; offcut at resident::000002
      0000:0101       e90000                    JMP       target
      0000:0104       8b06                      MOV       AX,[CS:offcut.name+2]
      target.tail:
      0000:0106       e90000                    JMP       target.tail ; target remains plain prose
      WHITESPACE_ONLY
      0000:0109       ff                        byte[1]
    ASM
    source.sub!("WHITESPACE_ONLY\n", "   \n")
    source.sub!('byte[1]', "byte[1] \xff".b)

    rendered = render(source)

    assert_equal 11, rendered.scan(/\\hypertarget\{xref-\d+\}/).length
    assert_equal 7, rendered.scan(/\\hyperlink\{xref-\d+\}/).length
    assert_match(/JMP\s+\(\*@\\hyperlink\{xref-\d+\}\{\\listingfont\\detokenize\{target\}\}@\*\)/, rendered)
    assert_match(/CS:\(\*@\\hyperlink\{xref-\d+\}\{\\listingfont\\detokenize\{offcut\.name\}\}@\*\)\+2/, rendered)
    assert_match(/Exact phase reference: \(\*@\\hyperlink\{xref-\d+\}\{\\listingfont\\detokenize\{resident::000001\}\}@\*\)/, rendered)
    rendered.lines.grep(/resident::000001 90/).each { |line| refute_includes line, '\\hyperlink' }
    refute_includes rendered.lines.grep(/Note: plain prose/).first, '\\hypertarget'
    assert_includes rendered, 'missing_overlay::0000:0100(j)'
    assert_includes rendered, '; target remains plain prose'
    assert_includes rendered, "byte[1] \xff".b
    assert_equal normalized(source), strip_link_markup(rendered)
  end

  def test_rejects_duplicate_label_definitions
    _stdout, stderr, status = run_renderer("duplicate:\nduplicate:\n")

    refute status.success?
    assert_includes stderr, 'Duplicate label definition: duplicate'
  end

  def test_wraps_long_comments_at_words_within_the_default_limit
    source = [
      "0000:0100       90                        NOP",
      "                ; DOS AH=4Ah shrinks the PSP-owned block to 1000h paragraphs. If it fails, common recovery copies 512 bytes over PSP:0000-01FF, executes there, restores host bytes at PSP:0100-02FF, but leaves PSP:0000-00FF corrupted.",
      "                ; Restore host entry bytes, derive the body base, reserve PSP:0100h as the eventual return, hook INT 24h, and search current/PATH directories. BP-relative DTA/path scratch extends into uninitialized COM allocation beyond the file image; those runtime bytes are not source data.",
      "                ; #{'word ' * 26}linked reference 0000:0100(j).",
      "hidden_buffer_resident::000000-hidden_buffer_resident::000079 eb78a0010900000020000000ffffda00000200000001f0ff0000, 00 × 96 ; resident header template",
    ].join("\n") + "\n"

    wrapped = strip_link_markup(render(source))
    assert wrapped.lines.all? { |line| line.chomp.length <= DEFAULT_COLUMNS }
    assert_match(/^ {16}; .*bytes at PSP:0100/, wrapped)
    assert_match(/^ {16}; .*DTA\/path scratch/, wrapped)
    assert_match(/^ {16}; resident header template/, wrapped)
  end

  def test_does_not_treat_a_quoted_semicolon_as_a_comment
    source = %(db "#{'word ' * 30}; #{'tail ' * 10}"\n)
    wrapped = strip_link_markup(render(source))

    assert wrapped.lines.all? { |line| line.chomp.length <= DEFAULT_COLUMNS }
    assert_equal 1, wrapped.count(';')
    assert_equal source.gsub(/\s/, ''), wrapped.gsub(/\s/, '')
  end

  def test_rejects_a_word_longer_than_the_limit
    _stdout, stderr, status = run_renderer("x" * (DEFAULT_COLUMNS + 1) + "\n")

    refute status.success?
    assert_includes stderr, "word longer than the #{DEFAULT_COLUMNS}-column limit"
  end

  private

  def render(source)
    stdout, stderr, status = run_renderer(source)
    assert status.success?, "#{stdout}\n#{stderr}"
    File.binread(File.join(@directory, 'listing.asm'))
  end

  def run_renderer(source)
    input = File.join(@directory, 'input.asm')
    capture = File.join(@directory, 'listing.asm')
    File.binwrite(input, source)
    environment = {
      'ASM_LISTING_PDF_CAPTURE' => capture,
      'PATH' => "#{@bin}:#{ENV.fetch('PATH')}",
    }
    stdout, stderr, status = Open3.capture3(
      environment, File.expand_path('asm_listing_pdf', __dir__), input,
    )
    [stdout, stderr, status]
  end

  def normalized(source)
    source.lines(chomp: true).map { |line| line.strip.empty? ? ' ' : line }.join("\n") + "\n"
  end

  def strip_link_markup(rendered)
    rendered
      .gsub(/\(\*@\\hypertarget\{xref-\d+\}\{\}@\*\)/, '')
      .gsub(/\(\*@\\hyperlink\{xref-\d+\}\{\\listingfont\\detokenize\{([^}]+)\}\}@\*\)/, '\\1')
  end
end
