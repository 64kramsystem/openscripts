# OpenScripts #

`OS` is a collection of some of my scripts for personal use:

- programming
  - `prettify_xml_files.rb`: prettifies the specified XML files
- sysadmin
  - `clean_kernel_packages.rb`: uninstall the redundant kernel packages, keeping only the current, and the latest (past or future)
  - `download_ubuntu_packages.rb`: downloads Ubuntu packages from the chosen distro; useful for people "manually backporting" packages (eg. `linux-firmware`)
  - `update_mainline_kernel.rb`: automatically installs the latest version of the current (or chosen) kernel, from the Ubuntu mainline builds
  - `install_btrfs_checker.sh`: monthly scrubs the BTRFS partitions and notifies the user on logon

I will slowly add all the remaining ones.

# Changelog #

- 2017/Jul/15: added `download_ubuntu_packages.rb`
- 2017/Jul/10: added `install_btrfs_checker.sh`
