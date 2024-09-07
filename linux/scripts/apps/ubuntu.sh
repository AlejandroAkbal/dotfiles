#!/bin/bash

printf "Making Ubuntu changes"

# Disable printer services
sudo systemctl disable cups --now
sudo systemctl disable cups-browsed --now

# Fix time difference in dual boot
timedatectl set-local-rtc 1 --adjust-system-clock

# Remove confirmation for shutdown and reboot
gsettings set org.gnome.SessionManager logout-prompt false

printf "Done making changes"
