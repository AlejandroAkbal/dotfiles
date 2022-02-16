#!/bin/bash

APP_NAME="Workrave"

printf "Installing $APP_NAME"

sudo add-apt-repository --yes ppa:rob-caelers/workrave

sudo apt update

sudo apt install -y workrave

printf "\n$APP_NAME successfully installed\n"
