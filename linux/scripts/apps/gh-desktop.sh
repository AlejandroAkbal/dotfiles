#!/bin/bash

APP_NAME="GitHub Desktop"
# https://github.com/shiftkey/desktop?tab=readme-ov-file#debianubuntu

printf "Installing $APP_NAME"

wget -qO - https://apt.packages.shiftkey.dev/gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/shiftkey-packages.gpg > /dev/null
sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/shiftkey-packages.gpg] https://apt.packages.shiftkey.dev/ubuntu/ any main" > /etc/apt/sources.list.d/shiftkey-packages.list'

sudo apt update

sudo apt install github-desktop

printf "\n$APP_NAME successfully installed\n"
