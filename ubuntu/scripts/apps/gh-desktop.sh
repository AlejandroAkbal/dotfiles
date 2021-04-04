#!/bin/bash

APP_NAME="GitHub Desktop"

printf "Installing $APP_NAME"

wget -qO - https://packagecloud.io/shiftkey/desktop/gpgkey | sudo tee /etc/apt/trusted.gpg.d/shiftkey-desktop.asc >/dev/null

sudo sh -c 'echo "deb [arch=amd64] https://packagecloud.io/shiftkey/desktop/any/ any main" > /etc/apt/sources.list.d/packagecloud-shiftky-desktop.list'

sudo apt-get update

sudo apt install github-desktop

printf "\n$APP_NAME successfully installed\n"
