#!/usr/bin/env ruby

require_relative 'kernel_packages_maintenance/kernel_version'

require 'simple_scripting/argv'

require 'shellwords'

class CleanKernelPackages

  def execute(dry_run: false, keep_previous: false)
    current_version = KernelVersion.find_current

    puts "Current kernel version: #{current_version}", ""

    installed_versions = find_installed_versions(current_version)

    puts "Currently installed package versions:", *installed_versions.map { |version| "- #{version}" }, ""

    versions_to_remove = find_versions_to_remove(current_version, installed_versions, keep_previous: keep_previous)

    if versions_to_remove.size > 0
      packages_to_remove = find_packages_to_remove(versions_to_remove)

      puts "Removing packages:", *packages_to_remove.map { |package| "- #{package}"}, ""

      remove_packages(packages_to_remove) unless dry_run
    else
      puts "Nothing to remove!"
    end
  end

  private

  def find_installed_versions(current_version)
    raw_packages_list = find_installed_packages("^linux-(headers|image|image-extra)-#{current_version.major}\\.#{current_version.minor}\\.")

    package_versions = raw_packages_list.map do |package_name|
      raw_version = package_name[/linux-\w+(-\w+)?-(\d+\.\d+\.\d+-\w+)/, 2] || raise("Version not identified: #{package_name}")
      KernelVersion.parse_version(raw_version)
    end

    # We catch both the linux-header and the linux-headers-generic, so we uniq them.
    #
    package_versions.uniq
  end

  def find_installed_packages(pattern)
    `aptitude search -w 120 ~i#{pattern.shellescape} | cut -c 5- | awk '{print $1}'`.split("\n")
  end

  def find_versions_to_remove(current_version, installed_versions, options = {})
    future_versions = installed_versions.select do |version|
      version > current_version
    end

    previous_versions = installed_versions.select do |version|
      version < current_version
    end

    versions_to_delete = previous_versions.sort

    versions_to_delete.pop if options[:keep_previous]

    versions_to_delete + future_versions.sort[0..-2] # Keep the latest future
  end

  def find_packages_to_remove(versions)
    package_matchers = versions.map do |version|
      version_pattern = "#{version.major}\\.#{version.minor}\\.#{version.patch}"

      # Aptitude doesn't support `\d` for matching digits.
      #
      if version.ongoing
        # Example: 4.10.0-14
        version_pattern << "-#{version.ongoing}\\b"
      elsif version.rc
        # Example: 4.12.0-041200rc7
        version_pattern << "-[0-9]{6}rc#{version.rc}\\b"
      else
        # Example: 4.12.0-041200
        version_pattern << "-[0-9]{6}\\b"
      end

      "~i^linux-(headers|image|image-extra)-#{version_pattern}".shellescape
    end.join(' ')

    `aptitude search -w 120 #{package_matchers} | cut -c 5- | awk '{print $1}'`.split("\n")
  end

  def remove_packages(packages)
    system("sudo aptitude purge -y #{packages.join(' ')}")
  end

end

if __FILE__ == $PROGRAM_NAME

  options = SimpleScripting::Argv.decode(
    ['-k', '--keep-previous', "Keep one previous version (the latest)"],
    ['-n', '--dry-run', "Dry run; doesn't remove any package"],
  )

  CleanKernelPackages.new.execute(options)

end
