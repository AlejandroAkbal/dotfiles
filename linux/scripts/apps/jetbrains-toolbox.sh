#!/bin/bash

APP_NAME="Jetbrains Toolbox"

printf "Installing $APP_NAME"

cd /tmp

wget https://download.jetbrains.com/toolbox/jetbrains-toolbox-2.1.1.18388.tar.gz -O jetbrains-toolbox.tar.gz

sudo tar -xzf jetbrains-toolbox.tar.gz -C /opt

sudo chmod +x /opt/jetbrains-toolbox/jetbrains-toolbox

/opt/jetbrains-toolbox/jetbrains-toolbox

rm jetbrains-toolbox.tar.gz

printf "\n$APP_NAME successfully installed\n"
