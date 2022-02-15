#!/bin/bash

APP_NAME="Flatpak"

printf "Installing $APP_NAME"

sudo apt install -y flatpak gnome-software-plugin-flatpak

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

printf "\n$APP_NAME successfully installed\n"
