#!/usr/bin/env crystal

require "uri"
require "http/client"
require "openssl"
require "option_parser"
require "file_utils"
require "progress_bar"

# Ubuntu's packages website is disgracefully unstable.
DOWNLOAD_PAGE_MAX_RETRIES = 3

# Specify this to download the current development version.
DEV_UBUNTU_VERSION_PARAM = "devel"

class DownloadWithProgress
  def execute(address : String, destination_file : String)
    uri = URI.parse(address)

    # HEAD to get size first
    head_response = HTTP::Client.head(address)
    raise "File not found!" if head_response.status_code == 404

    file_basename = File.basename(destination_file)
    file_size = head_response.headers["Content-Length"].to_i64

    bar = ProgressBar.new(
      total: file_size,
      width: 60,
      title: file_basename,
      format: "%t |%B| %p%% %e"
    )

    # Stream GET so we can update progress bar
    HTTP::Client.get(address) do |response|
      File.open(destination_file, "wb") do |file|
        buffer = Bytes.new(32_768)
        while (read_bytes = response.body_io.read(buffer)) > 0
          file.write(buffer[0, read_bytes])
          bar.increment(read_bytes)
        end
      end
    end

    bar.finish
  end
end

class DownloadUbuntuPackages
  INDEX_SERVER_ADDRESS             = "http://packages.ubuntu.com"
  PACKAGE_SERVER_ADDRESS           = "http://de.archive.ubuntu.com"
  ALTERNATE_PACKAGE_SERVER_ADDRESS = "http://security.ubuntu.com"
  DEFAULT_ARCHITECTURE             = "amd64"

  RELEASES_ADDRESS    = "https://releases.ubuntu.com"
  DAILY_BUILD_ADDRESS = "https://cdimage.ubuntu.com/daily-live/current"

  def execute(
    packages : Array(String),
    download_to : String = Dir.current,
    skip_ssl_verification : Bool = false,
    release : String? = nil,
    address_only : Bool = false,
  )
    OpenSSL::SSL.default_context.verify_mode = skip_ssl_verification ? OpenSSL::SSL::VerifyMode::NONE : OpenSSL::SSL::VerifyMode::PEER

    rel = resolve_release(release)

    packages.each do |package|
      package_download_page = find_and_open_package_download_page(rel, package)
      package_address = find_package_address(package_download_page, package)

      if address_only
        puts package_address
      else
        destination_file = compose_destination_file(package_address, download_to)

        if File.exists?(destination_file)
          puts ">>> File #{destination_file} exists; not downloading"
        else
          DownloadWithProgress.new.execute(package_address, destination_file)
        end
      end
    end
  end

  private def resolve_release(release : String?) : String
    case release
    when nil
      find_latest_release
    when DEV_UBUNTU_VERSION_PARAM
      find_latest_dev_release
    else
      release
    end
  end

  private def find_latest_release : String
    releases_page = HTTP::Client.get(RELEASES_ADDRESS).body
    # e.g. <img src="/icons/folder.gif" alt="[DIR]"> <a href="22.04/">22.04/</a> ... Ubuntu 22.04 LTS (Jammy Jellyfish)
    entries = releases_page.scan(/alt="\[DIR\]">\s*<a href="(\d{2}\.\d{2})[^>]*>[^<]+<\/a>.*?Ubuntu[\s\S]*?\(([A-Za-z]+)\s+[A-Za-z]+\)/)
    raise "Release not found!" if entries.empty?
    entries.max_by { |numeric, _| numeric }.last.downcase
  end

  private def find_latest_dev_release : String
    images_page = HTTP::Client.get(DAILY_BUILD_ADDRESS).body
    # e.g. <a href="mantic-desktop-amd64.iso">64-bit PC (AMD64) desktop image</a>
    dev = images_page[/"([a-z]+)-desktop-amd64\.iso"/, 1]
    raise "Development release not found!" unless dev
    dev
  end

  # Tries the default architecture first; if not found, tries the `all` architecture.
  private def find_and_open_package_download_page(release : String, package : String) : String
    package_download_address = download_address(release, DEFAULT_ARCHITECTURE, package)

    retries = 0
    begin
      response = HTTP::Client.get(package_download_address)
      html = response.body
      if html =~ /<title>Ubuntu.+Error<\/title>/
        raise "Package search yielded error page"
      end
      html
    rescue ex : HTTP::Client::Error
      raise ex if retries >= DOWNLOAD_PAGE_MAX_RETRIES
      retries += 1
      STDERR.puts "Error opening package download page, retrying (#{retries})..."
      sleep 1
      retry
    end
  end

  private def download_address(release : String, architecture : String, package : String) : String
    "#{INDEX_SERVER_ADDRESS}/#{release}/#{architecture}/#{package}/download"
  end

  # Locate the .deb URL inside the download page
  private def find_package_address(package_download_page : String, package : String) : String
    [PACKAGE_SERVER_ADDRESS, ALTERNATE_PACKAGE_SERVER_ADDRESS].each do |server_address|
      regex = /#{server_address}\/ubuntu\/pool\/\w+\/\w+\/.*?#{Regexp.escape(package)}_[^\s"']+\.deb/
      if match = package_download_page.match(regex)
        return match[0]
      end
    end
    raise "Package link match not found for #{package}"
  end

  private def compose_destination_file(package_address : String, destination_directory : String) : String
    file_basename = File.basename(package_address)
    File.join(destination_directory, file_basename)
  end
end

private def parse_commandline_arguments
  args = NamedTuple.new

  parser = OptionParser.parse do |parser|
    parser.banner =
      <<-HELP
        [packages] is a comma‑separated list of package names.
        [release]  is the Ubuntu release (focal, jammy ...).

        The architecture is always #{DownloadUbuntuPackages::DEFAULT_ARCHITECTURE}. If the file already exists in the destination path it will not be downloaded again.

        Use '--no-ssl-verification' for the current Jammy issue where opening a package download page raises an SSL certificate error.
      HELP

    parser.on("-d DIRECTORY", "--download-to=DIRECTORY", "Download directory; defaults to current path") do |arg|
      args = args.merge(download_to: arg)
    end

    parser.on("-s", "--skip-ssl-verification", "Disable SSL verification") do
      args = args.merge(skip_ssl_verification: true)
    end

    parser.on("-r RELEASE", "--release=RELEASE", "Ubuntu release; use '#{DEV_UBUNTU_VERSION_PARAM}' for development version") do |arg|
      args = args.merge(release: arg)
    end

    parser.on("-a", "--address-only", "Print the package download address without downloading") do
      args = args.merge(address_only: true)
    end

    parser.on("-h", "--help", "Show this message") do
      puts parser
      exit
    end

    parser.invalid_option do |option|
      STDERR.puts "Unknown option: #{option}", parser
      abort
    end
  end

  if ARGV.size != 1
    STDERR.puts "Only one packages argument is accepted.", parser
    abort
  end

  packages = ARGV[0].split(',')

  {packages, args}
end

def main
  packages, args = parse_commandline_arguments

  # BROKEN - can't splat union NTs
  DownloadUbuntuPackages.new.execute(packages, **args)
end

main
