# OpenScripts #

`OS` is a collection of some of my scripts for personal use:

- documents
  - `update_markdown_chapter_references`: generates/updates a Table Of Contents, and navigation links, in a collection of Markdown documents
  - `update_markdown_toc`: generates/updates a Table Of Contents, for a single Markdown document
- programming
  - `prettify_xml_files`: prettifies the specified XML files
  - `ship_gem`: ships a gem, performing all the maintenance operation (version increase, tag, build, push, ...)
- sysadmin
  - `clean_kernel_packages`: uninstall the redundant kernel packages, keeping only the current, and the latest (past or future)
  - `download_ubuntu_packages`: downloads Ubuntu packages from the chosen distro; useful for people "manually backporting" packages (eg. `linux-firmware`)
  - `install_btrfs_checker`: monthly scrubs the BTRFS partitions and notifies the user on logon
  - `install_smart_notifier`: notifies the user on logon, when smartd finds a problem with any disk
  - `update_mainline_kernel`: automatically installs the latest version of the current (or chosen) kernel, from the Ubuntu mainline builds

I will slowly add remaining or new ones.

# Changelog #

- 2017/Nov/11: added JSON support to `prettify_xml_files`, and renamed to `prettify` (ruby)
- 2017/Oct/20: added `ship_gem` (ruby)
- 2017/Oct/10: moved `github_create` to the new `geet` project
- 2017/Oct/06: added `github_create` (ruby)
- 2017/Sep/14: added `update_markdown_toc` (ruby)
- 2017/Sep/08: added `update_markdown_chapter_references`
- 2017/Sep/03: added `install_smart_notifier` (shell script)
- 2017/Jul/15: added `download_ubuntu_packages` (ruby)
- 2017/Jul/10: added `install_btrfs_checker` (shell script)
