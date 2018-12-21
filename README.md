# OpenScripts #

`OS` is a collection of some of my scripts for personal use:

- concurrency
  - `interruptible_job_scheduler.rb`: a scheduler for interruptible process-based job(s)
- documents
  - `update_markdown_chapter_references`: generates/updates a Table Of Contents, and navigation links, in a collection of Markdown documents
  - `update_markdown_toc`: generates/updates a Table Of Contents, for a single Markdown document
- git
  - `git_purge_empty_branches`: purge all the branches (local, and their remote tracked) without commits that aren't in master.
- programming
  - `prettify_xml_files`: prettifies the specified XML files
  - `ship_gem`: ships a gem, performing all the maintenance operation (version increase, tag, build, push, ...)
- sysadmin
  - `clean_kernel_packages`: uninstall the redundant kernel packages, keeping only the current, and the latest (past or future)
  - `downer`: download and automatically install packages/images from web pages
  - `download_ubuntu_packages`: downloads Ubuntu packages from the chosen distro; useful for people "manually backporting" packages (eg. `linux-firmware`)
  - `ejectdisk`: unmounts and powers off a device, or all the connected USB storage devices
  - `ownsync`: command line sync script for Owncloud/Nextcloud, with conflicts handling
  - `install_btrfs_checker`: monthly scrubs the BTRFS partitions and notifies the user on logon
  - `install_smart_notifier`: notifies the user on logon, when smartd finds a problem with any disk
  - `update_mainline_kernel`: automatically installs the latest version of the current (or chosen) kernel, from the Ubuntu mainline builds

I will slowly add remaining or new ones.
