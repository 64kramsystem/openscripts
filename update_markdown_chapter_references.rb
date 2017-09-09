#!/usr/bin/env ruby

require 'simple_scripting/argv'

class UpdateMarkdownChapterReferences

  LONG_HELP = <<~'STR'
    Update a series of markdown chapters, adding/updating the TOC, and the footing navigation links (next/previous).

    The script makes a few assumptions:

    - each file starts is named `<number>_<title>.md`
    - if a TOC file is specified, the other files must begin with number `1`
    - each file has an H1 title `# <title>`
    - navigation links are at the bootom of each document, in a single line starting with `[Previous: ` (or `[Next: `)

    Using the `--toc-file` option, it's possible to specify a file containing the TOC, but without having a numbered filename (eg. `README.md`).
  STR

  def execute(directory: '.', toc_file: nil)
    numbered_chapter_files = find_numbered_chapter_files(directory)
    toc_file ||= numbered_chapter_files[0]

    chapters_mapping = map_chapters(toc_file, numbered_chapter_files)

    update_file_table_of_contents(toc_file, chapters_mapping)

    chapters_mapping.keys.each_with_index do |chapter_file, file_index|
      update_navigation_links(chapter_file, file_index, chapters_mapping)
    end
  end

  private

  # SYSTEM LEVEL

  def find_numbered_chapter_files(directory)
    pattern = File.join(directory, '*.md')

    all_markdown_files = Dir[pattern].map { |filename| File.basename(filename)}

    chapter_files = all_markdown_files.select { |filename| filename[/^\d+_/] }

    raise "No files found!" if chapter_files.empty?

    chapter_files.sort
  end

  # FILE LEVEL

  def update_file_table_of_contents(toc_file, chapters_mapping)
    puts "Updating TOC in #{toc_file}..."

    content = IO.read(toc_file)

    remove_table_of_contents!(content)

    add_table_of_contents!(content, chapters_mapping)

    IO.write(toc_file, content)
  end

  def update_navigation_links(chapter_file, file_index, chapters_mapping)
    puts "Updating navigation links in #{chapter_file}..."

    content = IO.read(chapter_file)

    remove_navigation_links!(content)

    add_navigation_links!(content, file_index, chapters_mapping)

    IO.write(chapter_file, content)
  end

  # CONTENT LEVEL

  def map_chapters(toc_file, chapter_files)
    all_documents = [toc_file] + chapter_files

    all_documents.each_with_object({}) do |chapter_file, mapping|
      chapter_content = IO.read(chapter_file)
      title = chapter_content[/^# (.*)/, 1] || raise("Title not found in file #{chapter_file}")
      mapping[chapter_file] = title
    end
  end

  def remove_table_of_contents!(content)
    # Support the case where there is only H1 and not other headers.
    #
    content.sub!(/^## Table of contents.*?(^#|\Z)/m, '\1')
  end

  def add_table_of_contents!(content, chapters_mapping)
    table_of_contents = "## Table of contents\n\n"

    chapters_mapping.each do |chapter_file, chapter_title|
      chapter_number = find_chapter_number(chapter_file, chapters_mapping)
      entry = "#{chapter_number}. [#{chapter_title}](#{chapter_file})\n"
      table_of_contents << entry
    end

    table_of_contents << "\n"

    content.sub!(/^(# .*?)(^#|\Z)/m, "\\1#{table_of_contents}\\2")
  end

  def remove_navigation_links!(content)
    content.sub!(/^\[(Previous|Next): .*\n*\Z/, '')
  end

  def add_navigation_links!(content, file_index, chapters_mapping)
    navigation_links = []

    if file_index > 0
      previous_file = chapters_mapping.keys[file_index - 1]
      previous_chapter_title = chapters_mapping[previous_file]
      navigation_links << "[Previous: #{previous_chapter_title}](#{previous_file})"
    end

    if file_index < chapters_mapping.size - 1
      next_file = chapters_mapping.keys[file_index + 1]
      next_chapter_title = chapters_mapping[next_file]
      navigation_links << "[Next: #{next_chapter_title}](#{next_file})"
    end

    content << navigation_links.join(" | ") << "\n"
  end

  # STRING LEVEL

  def find_chapter_number(chapter_file, chapters_mapping)
    chapter_number = chapter_file[/^\d+/]

    # The TOC file may not have a number in the name.
    #
    if chapter_number
      chapter_number
    elsif chapter_file == chapters_mapping.keys[0]
      '0'
    else
      raise("Chapter number not found in file #{chapter_file}")
    end
  end
end

if __FILE__ == $0
  options = SimpleScripting::Argv.decode(
    ['-t', '--toc-file FILENAME', "TOC file; if not specified, the first detected chapter file is used"],
    '[directory]',
    long_help: UpdateMarkdownChapterReferences::LONG_HELP
  )

  UpdateMarkdownChapterReferences.new.execute(options)
end
