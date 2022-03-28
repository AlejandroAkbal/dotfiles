#!/bin/bash

printf "Making Ubuntu changes"

# Disable printer services
sudo systemctl disable cups --now
sudo systemctl disable cups-browsed --now

# Fix time difference in dual boot
timedatectl set-local-rtc 1 --adjust-system-clock

printf "Done making changes"
