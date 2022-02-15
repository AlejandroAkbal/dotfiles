#!/bin/bash

APP_NAME="Google Chrome"

printf "Installing $APP_NAME"

wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

sudo dpkg -i google-chrome-stable_current_amd64.deb

rm google-chrome-stable_current_amd64.deb

printf "\n$APP_NAME successfully installed\n"
