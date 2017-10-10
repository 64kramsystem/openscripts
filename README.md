# OpenScripts #

`OS` is a collection of some of my scripts for personal use:

- documents
  - `update_markdown_chapter_references.rb`: generates/updates a Table Of Contents, and navigation links, in a collection of Markdown documents
  - `update_markdown_toc.rb`: generates/updates a Table Of Contents, for a single Markdown document
- programming
  - `prettify_xml_files.rb`: prettifies the specified XML files
- sysadmin
  - `clean_kernel_packages.rb`: uninstall the redundant kernel packages, keeping only the current, and the latest (past or future)
  - `download_ubuntu_packages.rb`: downloads Ubuntu packages from the chosen distro; useful for people "manually backporting" packages (eg. `linux-firmware`)
  - `install_btrfs_checker.sh`: monthly scrubs the BTRFS partitions and notifies the user on logon
  - `install_smart_notifier.sh`: notifies the user on logon, when smartd finds a problem with any disk
  - `update_mainline_kernel.rb`: automatically installs the latest version of the current (or chosen) kernel, from the Ubuntu mainline builds

I will slowly add all the remaining ones.

# Changelog #

- 2017/Oct/10: moved `github_create.rb` to the new `geet` project
- 2017/Oct/06: added `github_create.rb`
- 2017/Sep/14: added `update_markdown_toc.rb`
- 2017/Sep/08: added `update_markdown_chapter_references.rb`
- 2017/Sep/03: added `install_smart_notifier.sh`
- 2017/Jul/15: added `download_ubuntu_packages.rb`
- 2017/Jul/10: added `install_btrfs_checker.sh`
