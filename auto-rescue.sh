#!/bin/bash
# Mount root as read/write
mount -o remount,rw /

# Disable Cage
systemctl disable cage-kiosk.service

# Restore boot to graphical desktop (LXDE)
raspi-config nonint do_boot_behaviour B4

# Update the repo
cd /home/pi/Slideshow
su - pi -c "git pull"

# Revert cmdline.txt to normal boot
sed -i 's| init=/boot/firmware/auto-rescue.sh||' /boot/firmware/cmdline.txt
sed -i 's| init=/boot/auto-rescue.sh||' /boot/cmdline.txt

# Continue normal boot process
exec /sbin/init
