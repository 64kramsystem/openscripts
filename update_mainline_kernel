#!/usr/bin/env ruby

require_relative 'kernel_packages_maintenance/kernel_version'
require_relative 'clean_kernel_packages'

require 'simple_scripting/argv'

require 'open-uri'
require 'ostruct'
require 'ruby-progressbar'
require 'uri'

class DownloadWithProgress

  def execute(address, destination_file)
    uri = URI(address)

    Net::HTTP.start(uri.host) do |http|
      response = http.request_head(address)

      file_basename = File.basename(destination_file)
      file_size = response['content-length'].to_i

      progress_bar = ProgressBar.create(title: "  #{file_basename}", total: file_size)

      File.open(destination_file, "wb") do |file|
        http.get(address) do |data_chunk|
          file << data_chunk
          progress_bar.progress += data_chunk.length
        end
      end

      progress_bar.finish
    end
  end

end

class UpdateMainlineKernel

  PPA_ADDRESS = "http://kernel.ubuntu.com/~kernel-ppa/mainline"
  KERNEL_TYPE = "generic"
  ARCHITECTURE = "amd64"
  DEFAULT_STORE_PATH = '/tmp'

  def execute(options = {})
    current_kernel_version = options[:install] ? decode_version_for_install(options[:install]) : KernelVersion.find_current
    store_path = options[:store_path] || DEFAULT_STORE_PATH

    puts "Current kernel version: #{current_kernel_version}"

    mainline_ppa_page = load_mainline_ppa_page

    all_patch_versions = find_all_patch_versions_for_kernel_version(mainline_ppa_page, current_kernel_version)

    puts "Latest 3 patch versions found: #{all_patch_versions.sort.last(3).join(', ')}"

    latest_patch_version = all_patch_versions.sort.last

    if latest_patch_version > current_kernel_version
      puts "Installing: #{latest_patch_version}"

      puts "Downloading packages..."

      package_addresses = find_kernel_package_addresses(latest_patch_version)
      package_files = download_package_files(package_addresses, store_path)

      if package_files.size > 0
        puts "Installing packages..."

        install_packages(package_files)

        CleanKernelPackages.new.execute
      end
    else
      puts "-> Nothing to do."
    end
  end

  private

  # Format: maj.min
  #
  def decode_version_for_install(raw_version)
    major, minor = raw_version.match(/^(\d)\.(\d+)$/).captures

    # Simulate a X.Y.0-rc0
    #
    KernelVersion.new(major, minor, 0, rc: 0)
  end

  def load_mainline_ppa_page
    open(PPA_ADDRESS).read
  end

  def find_all_patch_versions_for_kernel_version(mainline_ppa_page, version)
    # Examples (from 4.8+; previous rc versions also had suffixes):
    #
    #     href="v4.9.7/"
    #     href="v4.10-rc6/"
    #
    matching_links_found = mainline_ppa_page.scan(%r{href="v#{version.major}\.#{version.minor}(\.(\d+))?(-rc(\d+))?/"})

    matching_links_found.map do |_, patch, _, rc|
      KernelVersion.new(version.major, version.minor, patch, rc: rc)
    end
  end

  def find_kernel_package_addresses(version)
    kernel_page_address = "#{PPA_ADDRESS}/v#{version.major}.#{version.minor}"

    if version.rc
      kernel_page_address << "-rc#{version.rc}"
    elsif version.patch > 0
      kernel_page_address << ".#{version.patch}"
    end

    # The page has multiple identical links for each package (and seven for the common
    # headers), so we just pick the first of each.
    #
    kernel_page = open(kernel_page_address).read

    if kernel_page =~ /Build for #{ARCHITECTURE} succeeded/
      common_headers = kernel_page[/linux-headers-.+?_all\.deb/] || raise('common headers')
      specific_headers = kernel_page[/linux-headers-.+?-#{KERNEL_TYPE}_.+?_#{ARCHITECTURE}.deb/] || raise('spec. headers')
      image = kernel_page[/linux-image-.+?-#{KERNEL_TYPE}.+?_#{ARCHITECTURE}.deb/] || raise('image')

      [
        "#{kernel_page_address}/#{common_headers}",
        "#{kernel_page_address}/#{specific_headers}",
        "#{kernel_page_address}/#{image}"
      ]
    else
      puts "> Build failed! Exiting."

      []
    end
  end

  def download_package_files(package_addresses, destination_directory)
    package_addresses.map do |package_address|
      file_basename = File.basename(package_address)
      destination_file = File.join(destination_directory, file_basename)

      DownloadWithProgress.new.execute(package_address, destination_file)

      destination_file
    end
  end

  def install_packages(downloaded_files)
    `sudo dpkg -i #{downloaded_files.join(" ")}`
  end

end

# The web page link, architecture, and kernel type, all have a default.
#
if __FILE__ == $PROGRAM_NAME

  options = SimpleScripting::Argv.decode(
    [ '-i', '--install VERSION', 'Install a certain version [format: <maj.min>]' ],
    [ '-s', '--store-path PATH', 'Store packages to path (default: /tmp)' ],
  ) || exit

  UpdateMainlineKernel.new.execute(options)

end
