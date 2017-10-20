#!/usr/bin/env ruby

require 'simple_scripting/argv'

require 'rexml/document'

class XmlPrettifier

  def prettify_files(filenames, backup: false)
    filenames.each do |filename|
      puts "Prettifying #{filename}..."

      source_xml = IO.read(filename)

      IO.write("#{filename}.bak", source_xml) if backup

      prettified_xml = prettify_string(source_xml)

      IO.write(filename, prettified_xml)
    end

    nil
  end

  def prettify_string(xml)
    buffer = ''

    root = REXML::Document.new(xml)

    xml_formatter = REXML::Formatters::Pretty.new
    xml_formatter.compact = true
    xml_formatter.write(root, buffer)

    buffer
  end

end

if $PROGRAM_NAME == __FILE__
  params = SimpleScripting::Argv.decode(
    ['-b', '--backup', 'Backup original file, appending `.bak`'],
    '*filenames'
  ) || exit

  XmlPrettifier.new.prettify_files(params[:filenames], backup: params[:backup])
end
