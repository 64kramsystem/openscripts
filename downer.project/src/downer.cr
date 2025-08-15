require "option_parser"
require "uri"
require "http/client"
require "file_utils"

module HttpGetFollow
  private def http_get_follow(url : String, max_redirects : Int32 = 10) : String
    current = url

    max_redirects.times do
      HTTP::Client.get(current) do |response|
        if response.status.redirection?
          loc = response.headers["Location"]?
          raise "Redirect without Location header (#{response.status.code})" unless loc
          current = resolve_url(current, loc)
          next
        else
          return response.body_io.gets_to_end
        end
      end
    end

    raise "Too many redirects while fetching #{url}"
  end

  # Simplistic.
  #
  private def resolve_url(base_url : String, location : String) : String
    loc_uri = URI.parse(location)

    case location
    when loc_uri.scheme # absolute
      location
    when !location.starts_with?("/")
      raise "Unsupported redirect format: #{location}"
    else
      base = URI.parse(base_url)
      "#{base.scheme}://#{base.host}#{location}"
    end
  end
end

class Downer
  include HttpGetFollow

  # Keep parse_commandline_arguments()'s defaults in sync with these.
  #
  def execute(page_address : String, file_link_pattern : Regex, relative_path : Bool, wget : Bool, application : String?)
    file_link = find_file_link(page_address, file_link_pattern, relative_path: relative_path, wget: wget)
    package_file = download_file(file_link)
    install(package_file, application: application)
    File.delete(package_file) if package_file
  end

  private def download_page(address : String, use_wget : Bool) : String
    puts "Address: #{address}"

    if use_wget
      file = File.tempfile("downer")

      run!("wget", ["-O", file.path, address])

      File.read(file.path)
    else
      http_get_follow(address)
    end
  end

  private def find_file_link(page_address : String, file_link_pattern : Regex, *, relative_path : Bool, wget : Bool) : String
    page_content = download_page(page_address, wget)

    md = file_link_pattern.match(page_content)
    file_link = md ? md[0] : begin
      puts page_content
      raise "File link not Found!"
    end

    if relative_path
      base = URI.parse(page_address)
      "#{base.scheme}://#{base.host}#{file_link}"
    else
      file_link
    end
  end

  private def download_file(file_link : String) : String
    puts "- downloading link #{file_link}..."

    tmp = File.tempfile("downer")
    begin
      http_download_to(file_link, tmp.path)
      new_filename = "/tmp/#{File.basename(file_link)}"
      File.rename(tmp.path, new_filename)
      new_filename
    ensure
      tmp.close
      # If rename failed, cleanup the temp file.
      File.delete(tmp.path) if File.exists?(tmp.path)
    end
  end

  private def install(package_file : String, *, application : String?)
    if application
      # NOTE: expects a single executable; no extra args are parsed here.
      run!("sudo", [application, package_file])
    else
      ext = File.extname(package_file)
      ext = ext.empty? ? package_file.split('.').last? : ext.lstrip('.')
      raise "Package extension not found" unless ext

      method = "install_#{ext}_package"
      raise "WRITEME" if true
      # if self.responds_to?(method)
      #   self.send(method, package_file)
      # else
      #   raise "Package extension not supported: #{ext}"
      # end
    end
  end

  # ---- Per-extension installers ----

  private def install_deb_package(package_file : String)
    puts "- installing #{package_file}..."
    run!("sudo", ["gdebi", "--non-interactive", package_file])
  end

  private def install_run_package(package_file : String)
    puts "- installing #{package_file}..."
    File.chmod(package_file, File::Permissions.new(0o755))
    run!("sudo", [package_file])
  end

  # dmg support (macOS): only single partition DMG containing a single .pkg
  private def install_dmg_package(package_file : String)
    puts "- attaching #{package_file}..."

    attachment_output = run_capture!("sudo", ["hdiutil", "attach", package_file])
    # Normalize encoding implicitly by treating as UTF-8 string (Crystal strings are UTF-8)

    volumes_attached = scan_lines(attachment_output, /\/Volumes\/[^\n]*/)
    raise "Only single-partition DMG images are supported!" unless volumes_attached.size == 1
    installer_volume = volumes_attached[0]

    pkg_files = Dir.glob("#{installer_volume}/*.pkg")
    raise "Only volumes with a single PKG file are supported!" unless pkg_files.size == 1
    installation_pkg_file = pkg_files[0]

    begin
      install_pkg_package(installation_pkg_file)
    ensure
      # Always detach what we attached
      volumes_attached.each do |volume|
        begin
          run!("sudo", ["hdiutil", "detach", volume])
        rescue
          # If detach fails, surface an informative message but continue
          STDERR.puts "Warning: failed to detach #{volume}"
        end
      end
    end
  end

  private def install_pkg_package(package_file : String)
    puts "- installing #{package_file}..."
    run!("sudo", ["installer", "-package", package_file, "-target", "/"])
  end

  # ---- Helpers ----

  # Run command, raising on non-zero exit.
  private def run!(cmd : String, args : Array(String)) : Nil
    status = Process.run(cmd, args: args, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    raise "Command failed: #{([cmd] + args).join(" ")}" unless status.success?
  end

  # Run command and capture combined stdout/stderr; raise on non-zero exit.
  private def run_capture!(cmd : String, args : Array(String)) : String
    out = IO::Memory.new
    raise "WRITEME" if true
    # status = Process.run(cmd, args: args, output: out, error: out)
    # raise "Command failed: #{([cmd] + args).join(" ")}\n#{out.to_s}" unless status.success?
    out.to_s
  end

  # Follow redirects and stream body to a file.
  private def http_download_to(url : String, path : String, max_redirects : Int32 = 10) : Nil
    current = url
    max_redirects.times do
      HTTP::Client.get(current) do |response|
        code = response.status_code
        if {301, 302, 303, 307, 308}.includes?(code)
          loc = response.headers["Location"]?
          raise "Redirect without Location header (#{code})" unless loc
          current = resolve_url(current, loc)
          next
        else
          File.open(path, "w") do |f|
            IO.copy(response.body_io, f)
          end
          return
        end
      end
    end
    raise "Too many redirects while downloading #{url}"
  end

  private def scan_lines(text : String, rx : Regex) : Array(String)
    results = [] of String
    text.scan(rx) { |m| results << m[0] }
    results
  end
end

private def parse_commandline_arguments
  opt_args = {
    relative_path: false,
    wget:          false,
    application:   nil,
  }

  parser = OptionParser.parse do |parser|
    parser.banner = <<-HELP
      Usage: #{File.basename(PROGRAM_NAME)} [options] page_address file_link_pattern

      This script is meant to be used only internally; it doesn't employ any form of protection against malicious attacks.

      HELP

    parser.on("-a APPLICATION", "--application=APPLICATION", "Use the given application") do |arg|
      opt_args = opt_args.merge(application: arg)
    end

    parser.on("-r", "--relative-path", "Assume that the URL path is relative") do
      opt_args = opt_args.merge(relative_path: true)
    end

    parser.on("-w", "--wget", "Use wget to download the page") do
      opt_args = opt_args.merge(wget: true)
    end

    parser.on("-h", "--help", "Show this message") do
      puts parser
      exit
    end

    parser.invalid_option do |option|
      STDERR.puts "Unknown option: #{option}", "", parser
      abort
    end
  end

  if ARGV.size != 2
    STDERR.puts "page_address and file_link_pattern are required.", "", parser
    abort
  end

  page_address = ARGV[0]
  file_link_pattern = Regex.new(ARGV[1])

  {page_address, file_link_pattern, opt_args}
end

def main
  page_address, file_link_pattern, opt_args = parse_commandline_arguments
  Downer.new.execute(page_address, file_link_pattern, **opt_args)
end

main
