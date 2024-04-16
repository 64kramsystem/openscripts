# OpenScripts

OpenScripts is a collection of some of my scripts/generic programs for personal use:

- algorithms
  - `ll_node.rb`: a simple implementation of a (singly-)linked list, that I sometimes used when exercising
- concurrency
  - `interruptible_job_scheduler.rb`: a scheduler for interruptible process-based job(s)
- documents
  - `generate_wiki_home_toc`: generates the `Home.md` file of a (GitHub) wiki repository, with a table of contents
  - `update_markdown_chapter_references`: generates/updates a Table Of Contents, and navigation links, in a collection of Markdown documents
  - `update_markdown_toc`: generates/updates a Table Of Contents, for a single Markdown document
- generic
  - `bedtime`: sets two (systemd) timers, one to suspend the computer, and the other to shut it down
  - `compress_dvd`: compresses an unencrypted DVD iso to h265/aac
  - `convert_cb_archive_to_pdf`: convert CBR/CBZ files to PDF
  - `convert_video_to_animated_gif`: convert a video to animated gid (via FFmpeg)
  - `control_music_player`: performs actions on a music player running in the background (supports Clementine, MPV, GMusicBrowser...)
  - `encode_to_m4a`: encodes and normalizes input files to m4a, using ffmpeg/libsdk_aac
  - `fill_dhl_packet_slip`: fills a DHL packet slip, and opens an OpenDocument page with it
  - `fill_labels`: prepares an OpenDocument page with addresses, to be printed on a standard A4 page with 96x50.8mm labels
  - `mk_invoice`: prepares a generic (software engineering) invoice in Office Open XML format, using a template, and the data provided in the configuration file
  - `normalize_flac_tracks`: renames, removes the current tags, and add replay gain, to flac files
  - `plot_2y_diagram`: plots a diagram with two y scales from a text file, via GNU Plot (and Ruby)
  - `plot_diagram`: plots a diagram from a text file, via GNU Plot (and Ruby),  with better support for batch processing than `plot_2y_diagram`
  - `record_desktop`: records a video of the desktop, using FFmpeg
  - `spell`: spell a phrase, with customizable alphabets
  - `split_cue_audio_file`: splits an audio file based on the provided cue file
  - `tag_mp3s_bpm`: tag mp3 files with the BPM field, using the Mixxx analysis
  - `texerak`: convenient wrapper around Tesseract, to OCR images/documents
- git
  - `git_find_default_branch`: finds and prints the default branch; if 'origin/HEAD' is not present, it sets it
  - `git_maintain_branches`: purge all the branches (local, and their remote tracked) without commits that aren't in the main branch; also syncs with upstream
  - `git_rename_commits`: rename git commits, using the old git (`filter-branch`) method
- programming
  - `build_kernel`: builds the Linux kernel, with some automations
  - `git_full_delete_branch`: checked deletion of branch (local and remote)
  - `git_merge_file_commits`: Merge the commits including a given file, in a Git repository
  - `meld`: wrapper around meld, that opens two blank panels, if no files are passed
  - `prettify`: prettifies files; supports XML and JSON
  - `rename_variables`: rename variables/constants with composite names
  - `ship_gem`: ships a gem, performing all the maintenance operation (version increase, tag, build, push, ...)
  - `unpack_gem`: unpacks a gem, with additional operations like directory creation, gemspec extraction (when not present), etc.
- system
  - `add_resolution_to_display`: add the given resolution to the display adapter, using `xrandr`
  - `clean_kernel_packages`: uninstall the redundant kernel packages, keeping only the current, and the latest (past or future)
  - `clean_recents`: clean the recent used file entries whose basename matches the specified patterns
  - `connect_bt_device`: connects a BT device, working around the complete garbage that is Bluetooth, Bluez, and the BT Ubuntu support
  - `desnapped`: starts the snap services, run the specified snap, and stops the snapd services
  - `downer`: download and automatically install packages/images from web pages
  - `download_ubuntu_packages`: downloads Ubuntu packages from the chosen distro; useful for people "manually backporting" packages (eg. `linux-firmware`)
  - `cpfloppy`: copy the content of multiple floppy images (IMG) to a specified dir
  - `ejectdisk`: unmounts and powers off a device, or all the connected USB storage devices
  - `ft(_function)`: very handy script for extracting a token/line from the output of a command
  - `gitio`: generate a short GitHub URL, and copy it to the clipboard
  - `install_btrfs_checker`: monthly scrubs the BTRFS partitions and notifies the user on logon
  - `install_smart_notifier`: notifies the user on logon, when smartd finds a problem with any disk
  - `maestral_upgrade`: upgrades and restarts Maestral
  - `manage_bt`: enable a BT device if present, opens the BT manager, then disables the device
  - `mkfloppy`: create a floppy image (IMG) from the specified files/dirs
  - `mylast`: runs the last executed MySQL query, and copies the result to the clipboard
  - `mysql_collect_stats`: collects MySQL server statistics over a session (global status values), in a convenient structure for processing
  - `mysql_plot_diagrams`: plots diagrams (via GNU Plot), with the stats collected via `mysql_collect_stats`
  - `mystart`/`mystop`: start/stop MySQL, automatically switching between version, and preparing the data
  - `ownsync`: command line sync script for Owncloud/Nextcloud, with conflicts handling
  - `patch_acpi_s3_support`: patch and hook the DSDT tables with S3 support (see [article](https://saveriomiroddi.github.io/Enabling-the-S3-sleep-suspend-on-the-Lenovo-Yoga-7-AMD-Gen-7-and-possibly-others/))
  - `purge_trash`: purge the trash files trashed before a certain threashold
  - `script_template`: create a Bash script template, and sets the permissions
  - `send_display_to_sleep`: send the display to sleep, working around GNOME's screensaver interference
  - `upgrade_bluez_from_source`: upgrade the system Bluez to the latest version, from source
  - `update_mainline_kernel`: automatically installs the latest version of the current (or chosen) kernel, from the Ubuntu mainline builds
  - `winetemplate`: conveniently run Wine programs, stored in a Git repository with per-program branches
  - `winetmp`: conveniently run Wine applications in a temporary, sandboxed, environment
  - `xcalib_safe`: wrapper around xcalib, which detects error states, and warns the user (and exits with error code)

I keep adding new content/update old ones.
