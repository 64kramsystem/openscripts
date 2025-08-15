#!/usr/bin/env crystal

require "uri"
require "http/client"
require "openssl"
require "option_parser"
require "file_utils"
require "progress_bar"

# Ubuntu's packages website is disgracefully unstable.
#
DOWNLOAD_PAGE_MAX_RETRIES = 3

# Specify this to download the current development version.
#
DEV_UBUNTU_VERSION_PARAM = "devel"

class DownloadWithProgress
  # Rough space taken by the right-side summary (percent, sizes, ETA)
  SUMMARY_BUDGET = 40
  MIN_BAR        = 10

  def execute(address : String, destination_file : String)
    head = HTTP::Client.head(address)
    raise "File not found!" if !head.success?

    file_basename = File.basename(destination_file)
    total = head.headers["Content-Length"].to_i32
    bar_width, title = compute_bar_width(file_basename)
    theme = Progress::Theme.new(width: bar_width, bar_start: "#{title} [", bar_end: "]")

    theme = Progress::Theme.new(
      width: bar_width,
      bar_start: "#{title} [",
      bar_end: "]"
    )

    HTTP::Client.get(address) do |response|
      File.open(destination_file, "wb") do |file|
        bar = Progress::IOBar.new(total: total, theme: theme)
        writer = bar.progress_writer
        IO.copy(response.body_io, IO::MultiWriter.new(file, writer))
        bar.finish! if !bar.done?
      end
    end
  end

  private def compute_bar_width(file_basename : String) : {Int32, String}
    cols = `tput cols`.to_i

    chrome = 3 # " [" + "]"
    title_max = cols - SUMMARY_BUDGET - MIN_BAR - chrome
    title_max = 0 if title_max < 0

    title = ellipsize(file_basename, title_max)

    bar_width = cols - SUMMARY_BUDGET - title.size - chrome
    bar_width = MIN_BAR if bar_width < MIN_BAR

    {bar_width, title}
  end

  private def ellipsize(string : String, max : Int32) : String
    return string if string.size <= max
    return "…" if max <= 1
    string.chars.first(max - 1).join + "…"
  end
end

class DownloadUbuntuPackages
  INDEX_SERVER_ADDRESS             = "https://packages.ubuntu.com"
  PACKAGE_SERVER_ADDRESS           = "http://de.archive.ubuntu.com"
  ALTERNATE_PACKAGE_SERVER_ADDRESS = "http://security.ubuntu.com"
  DEFAULT_ARCHITECTURE             = "amd64"

  # It seems that there is no programmatic way to find the releases.
  # The below seem to be reasonably robust; the releases page doesn't include releases under development,
  # so we gather the name from the daily build.
  #
  RELEASES_ADDRESS    = "https://releases.ubuntu.com"
  DAILY_BUILD_ADDRESS = "https://cdimage.ubuntu.com/daily-live/current"

  # Keep parse_commandline_arguments()'s defaults in sync with these.
  #
  def execute(
    packages : Array(String),
    download_to : String = Dir.current,
    release : String? = nil,
    address_only : Bool = false,
  )
    if release.nil?
      release = find_latest_release
    elsif release == DEV_UBUNTU_VERSION_PARAM
      release = find_latest_dev_release
    end

    packages.each do |package|
      package_download_page = find_and_open_package_download_page(release, package)
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

  private def find_latest_release : String
    # Sample:
    #
    #   <img src="/icons/folder.gif" alt="[DIR]"> <a href="22.04.1/">22.04.1/</a>                2022-08-11 11:16    -   Ubuntu 22.04.1 LTS (Jammy Jellyfish)
    #   <img src="/icons/folder.gif" alt="[DIR]"> <a href="22.10/">22.10/</a>                  2022-10-20 17:11    -   Ubuntu 22.10 (Kinetic Kudu)
    #
    # The timestamp can't be used, because an older release may be uploaded after a newer one.
    #
    releases_page = HTTP::Client.get(RELEASES_ADDRESS).body
    entries = releases_page.scan(/alt="\[DIR\]"> <a href="(\d\d\.\d\d).+?\((\w+) \w+\)$/m)
    raise "Release not found!" if entries.empty?
    entries.max_by { |entry| entry[0] }[2].downcase
  end

  private def find_latest_dev_release : String
    # Sample:
    #
    #   <a href="lunar-desktop-amd64.iso">64-bit PC (AMD64) desktop image</a>
    #
    images_page = HTTP::Client.get(DAILY_BUILD_ADDRESS).body
    dev = images_page[/"([a-z]+)-desktop-amd64\.iso"/, 1]
    raise "Development release not found!" unless dev
    dev
  end

  # Tries the default architecture first; if not found, tries the `all`.
  #
  private def find_and_open_package_download_page(release : String, package : String) : String
    # If the package has "all" architecture, using the specific architecture address
    # will lead to a page which still has the "all" architecture links.
    #
    package_download_address = download_address(release, DEFAULT_ARCHITECTURE, package)

    retries = 0

    while true
      begin
        # Search errors yield an error page, but with HTTP error status 🤦
        #
        response = HTTP::Client.get(package_download_address)

        if response.status.redirection?
          raise "Package download address is a redirect!"
        elsif !response.status.success?
          raise "Package download address returned error status: #{response.status}"
        end

        return response.body
      rescue ex
        raise ex if retries >= DOWNLOAD_PAGE_MAX_RETRIES
        retries += 1
        STDERR.puts "Error opening package download page, retrying (#{retries})..."
        sleep 1.second
      end
    end
  end

  private def download_address(release : String, architecture : String, package : String) : String
    "#{INDEX_SERVER_ADDRESS}/#{release}/#{architecture}/#{package}/download"
  end

  # Sample:
  #
  #   http://de.archive.ubuntu.com/ubuntu/pool/<REPO>/z/zfs-linux/zfsutils-linux_.+?_amd64.deb
  #
  # REPO: `main`, `universe`
  #
  private def find_package_address(package_download_page : String, package : String) : String
    [PACKAGE_SERVER_ADDRESS, ALTERNATE_PACKAGE_SERVER_ADDRESS].each do |server_address|
      package_link_regex = %r{
        #{server_address}/ubuntu/pool/\w+/
        \w+/.+?/
        #{Regex.escape(package)}_.+?_\w+.deb
      }x

      if match = package_download_page.match(package_link_regex)
        return match[0]
      end
    end

    puts package_download_page

    raise "Package link match not found for #{package}"
  end

  private def compose_destination_file(package_address : String, destination_directory : String) : String
    file_basename = File.basename(package_address)
    File.join(destination_directory, file_basename)
  end
end

private def parse_commandline_arguments
  opt_args = {
    download_to:  Dir.current,
    release:      nil,
    address_only: false,
  }

  # The server, architecture, and kernel type, all have a default.
  #
  parser = OptionParser.parse do |parser|
    parser.banner =
      <<-HELP
      Usage: #{File.basename(PROGRAM_NAME)} [options] <*packages>

      [packages] is a comma‑separated list of package names.
      [release]  is the Ubuntu release (focal, jammy ...).

      The architecture is always #{DownloadUbuntuPackages::DEFAULT_ARCHITECTURE}. If the file already exists in the destination path it will not be downloaded again.

      If a package is found in the destination path, it's not downloaded.

      HELP

    parser.on("-d DIRECTORY", "--download-to=DIRECTORY", "Download directory; defaults to current path") do |arg|
      opt_args = opt_args.merge(download_to: arg)
    end

    parser.on("-r RELEASE", "--release=RELEASE", "Ubuntu release; use '#{DEV_UBUNTU_VERSION_PARAM}' for development version") do |arg|
      opt_args = opt_args.merge(release: arg)
    end

    parser.on("-a", "--address-only", "Print the package download address without downloading") do
      opt_args = opt_args.merge(address_only: true)
    end

    parser.on("-h", "--help", "Show this message") do
      puts parser
      exit
    end

    parser.invalid_option do |option|
      STDERR.puts "Unknown option: #{option}", "", parser
      exit 1
    end
  end

  if ARGV.size != 1
    STDERR.puts "Only one packages argument is accepted.", "", parser
    exit 1
  end

  packages = ARGV[0].split(',')

  {packages, opt_args}
end

def main
  packages, opt_args = parse_commandline_arguments
  DownloadUbuntuPackages.new.execute(packages, **opt_args)
end

main
