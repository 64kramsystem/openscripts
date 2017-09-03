#!/bin/bash

set -o errexit

# Variables ####################################################################

username=$(who | awk '{print $1}')
user_home=$(getent passwd $username | cut -f6 -d:)
status_file=/var/lib/btrfs_scrub_status.txt
cron_file=/etc/cron.monthly/scrub_btrfs
notification_script=$user_home/bin/check_btrfs_scrub.sh
startup_application_definition="$user_home/.config/autostart/Check BTRFS scrub.desktop"

# Help and explanation #########################################################

# The BTRFS scrub actually stores the result in /var/lib/btrfs/scrub.status.<UUID>,
# but it's easier just to capture the `btrfs scrub` output.

if [[ $0 == '-h' || $1 == '--help' ]]; then
  echo "Usage: install_btrfs_checker.sh"
  echo
  echo "Install the scripts for monthly scrubbing the BTRFS partitions and notifying the user on logon."
  echo ""
  echo "Files installed:"
  echo "- $cron_file: cron job for monthly check"
  echo "- $notification_script: notification script"
  echo "- $startup_application_definition: notification script startup definition"
  echo
  exit
fi

# Cron job #####################################################################

echo "Installing $cron_file ..."

cat <<TEXT | sudo tee $cron_file > /dev/null
#!/bin/bash

rm -f $status_file $status_file.tmp

btrfs_partitions=\$(mount | grep btrfs | awk '{print \$1}')

for partition in \$btrfs_partitions; do
  btrfs scrub start \$partition

  # For a little, the output will be \`no stats available\`, so we start with
  # the sleep.
  #
  while true; do
    sleep 60

    if [[ \$(btrfs scrub status \$partition) != *running* ]]; then
      break
    fi
  done

  btrfs scrub status \$partition >> $status_file.tmp
done

chown $username: $status_file.tmp
mv $status_file.tmp $status_file

TEXT

sudo chmod 755 $cron_file

# Notifier #####################################################################

echo "Installing $notification_script ..."

cat <<TEXT > $notification_script
#!/bin/bash

if [[ -f $status_file && \$(cat $status_file) != "" ]]; then
  zenity --info --text="\$(cat $status_file)"
  > $status_file
fi
TEXT

chmod 755 $notification_script

# Startup application definition ###############################################

echo "Installing $startup_application_definition ..."

cat <<TEXT > "$startup_application_definition"
[Desktop Entry]
Encoding=UTF-8
Version=0.9.4
Type=Application
Name=Check BTRFS scrub
Comment=
Exec=$notification_script
OnlyShowIn=XFCE;
StartupNotify=false
Terminal=false
Hidden=false

TEXT
