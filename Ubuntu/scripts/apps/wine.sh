#!/bin/bash

APP_NAME="realvnc-viewer"

printf "Installing $APP_NAME"

sudo dpkg --add-architecture i386

wget -nc https://dl.winehq.org/wine-builds/winehq.key -O winehq.key

sudo apt-key add winehq.key

rm winehq.key

sudo add-apt-repository 'deb https://dl.winehq.org/wine-builds/ubuntu/ focal main'

sudo apt update

sudo apt install -y --install-recommends winehq-stable

printf "\n$APP_NAME successfully installed\n"
