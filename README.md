# OpenScripts #

`OS` is a collection of some of my scripts for personal use:

- concurrency
  - `interruptible_job_scheduler.rb`: a scheduler for interruptible process-based job(s)
- documents
  - `generate_wiki_home_toc`: generates the `Home.md` file of a (GitHub) wiki repository, with a table of contents
  - `update_markdown_chapter_references`: generates/updates a Table Of Contents, and navigation links, in a collection of Markdown documents
  - `update_markdown_toc`: generates/updates a Table Of Contents, for a single Markdown document
- git
  - `git_purge_empty_branches`: purge all the branches (local, and their remote tracked) without commits that aren't in master.
- programming
  - `prettify`: prettifies files; supports XML and JSON
  - `ship_gem`: ships a gem, performing all the maintenance operation (version increase, tag, build, push, ...)
- "real-world"
  - `encode_to_m4a`: encodes and normalizes input files to m4a, using ffmpeg/libsdk_aac
  - `fill_labels`: prepares an OpenDocument with addresses, to be printed on a standard A4 page with 96x50.8mm labels
  - `mk_invoice`: prepares a generic (software engineering) invoice in Office Open XML format, using a template, and the data provided in the configuration file
  - `plot_diagram`: plots a diagram from a text file, via GNU Plot (and Ruby),  with better support for batch processing than `plot_2y_diagram`
  - `plot_2y_diagram`: plots a diagram with two y scales from a text file, via GNU Plot (and Ruby)
  - `spell`: spell a phrase, with customizable alphabets
- system (user facing)
  - `connect_bt_device`: connects a BT device, working around the complete garbage that is Bluetooth, Bluez, and the BT Ubuntu support
  - `ejectdisk`: unmounts and powers off a device, or all the connected USB storage devices
  - `ownsync`: command line sync script for Owncloud/Nextcloud, with conflicts handling
- system (sysadmin)
  - `clean_kernel_packages`: uninstall the redundant kernel packages, keeping only the current, and the latest (past or future)
  - `downer`: download and automatically install packages/images from web pages
  - `download_ubuntu_packages`: downloads Ubuntu packages from the chosen distro; useful for people "manually backporting" packages (eg. `linux-firmware`)
  - `ft(_function)`: very handy script for extracting a token/line from the output of a command
  - `gitio`: generate a short GitHub URL, and copy it to the clipboard
  - `install_btrfs_checker`: monthly scrubs the BTRFS partitions and notifies the user on logon
  - `install_smart_notifier`: notifies the user on logon, when smartd finds a problem with any disk
  - `mysql_collect_stats`: collects MySQL server statistics over a session (global status values), in a convenient structure for processing
  - `mysql_plot_diagrams`: plots diagrams (via GNU Plot), with the stats collected via `mysql_collect_stats`
  - `purge_trash`: purge the trash files trashed before a certain threashold
  - `update_mainline_kernel`: automatically installs the latest version of the current (or chosen) kernel, from the Ubuntu mainline builds
  - `winetmp`: conveniently run Wine applications in a temporary, sandboxed, environment

I will slowly add remaining or new ones.

## Latest additions

Latest additions (not including updates):

- 2020/Jan/25: `ft(_function)`
- 2020/Jan/01: `purge_trash`
- 2019/Dec/06: `mysql_collect_stats` and `mysql_plot_diagrams`
- 2019/Oct/23: `fill_labels`
- 2019/Oct/21: `gitio`
- 2019/Sep/03: `encode_to_m4a`
- 2019/Aug/15: `plot_diagram` and `plot_2y_diagram`
- 2019/Jul/07: `winetmp`
- 2019/Apr/30: `spell`
- 2019/Mar/31: `mk_invoice`
- 2019/Mar/26: `connect_bt_device`
- 2019/Mar/18: `generate_wiki_home_toc`
- 2018/Dec/20: `downer`
