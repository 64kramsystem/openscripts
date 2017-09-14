#!/usr/bin/env ruby

require 'simple_scripting/argv'

class UpdateMarkdownChapterToc
  LONG_HELP = <<~STR
    Update the table of contents of markdown document.

    The script makes a few assumptions:

    - the TOC header is `## TABLE OF CONTENTS` (case insensitive)
    - all the headers start at least at level 2 (`##`)

    The TOC will be inserted at the top of the document.

    If all the chapters will be found as uppercase, the TOC will be in uppercase as well.
  STR

  def execute(document_file)
    content = IO.read(document_file)

    remove_table_of_contents!(content)

    chapter_headers = find_chapter_headers(content)

    table_of_contents = prepare_table_of_contents(content, chapter_headers)

    prepend_table_of_contents!(content, table_of_contents)

    IO.write(document_file, content)
  end

  private

  # MAIN ACTIONS

  def remove_table_of_contents!(content)
    # Support the case where there is only H1 and not other headers.
    #
    content.sub!(/^## Table of contents.*?(^#|\Z)/im, '\1')
  end

  # Returns an array of the chapter lines.
  #
  def find_chapter_headers(content)
    content.lines.select { |line| line.start_with?('#') }
  end

  def prepare_table_of_contents(content, chapter_headers)
    toc = "## Table of contents\n\n"

    if all_headers_upper_case?(chapter_headers)
      toc.upcase!
    end

    chapter_headers.each do |chapter_header|
      level_symbol, title = chapter_header.match(/^(#+) (.*)/).captures
      level = level_symbol.size

      entry = "  " * (level - 2) + "- " + title + "\n"

      toc << entry
    end

    toc + "\n"
  end

  def prepend_table_of_contents!(content, table_of_contents)
    content.sub!(/\A/, table_of_contents)
  end

  # HELPERS

  def all_headers_upper_case?(chapter_headers)
    chapter_headers.join == chapter_headers.join.upcase
  end
end

if __FILE__ == $0
  options = SimpleScripting::Argv.decode(
    'document',
    long_help: UpdateMarkdownChapterToc::LONG_HELP
  )

  UpdateMarkdownChapterToc.new.execute(options[:document])
end
